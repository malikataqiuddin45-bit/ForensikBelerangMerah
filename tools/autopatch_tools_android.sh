#!/usr/bin/env bash
set -euo pipefail

echo "===> Autopatch: kawinkan tools/ dengan android/ (signing + gradle props + guard)"

ROOT="$(pwd)"
ANDROID_DIR="$ROOT/android"

if [ ! -d "$ANDROID_DIR" ]; then
  echo "ERROR: Folder android/ tiada. Jika ini projek Expo managed, jalankan:"
  echo "  npx expo prebuild --platform android"
  exit 1
fi

# 1) Pastikan gradlew executable
chmod +x "$ANDROID_DIR/gradlew" || true

# 2) Sediakan keystore dari ENV (jika ANDROID_KEYSTORE_BASE64 diset)
if [ -n "${ANDROID_KEYSTORE_BASE64:-}" ]; then
  echo "==> Menjana keystore dari ANDROID_KEYSTORE_BASE64"
  mkdir -p "$ANDROID_DIR/app/keystores"
  echo "$ANDROID_KEYSTORE_BASE64" | base64 -d > "$ANDROID_DIR/app/keystores/release.jks"
  echo "[OK] Keystore ditulis ke android/app/keystores/release.jks"
fi

# 3) Patch gradle.properties untuk pick up signing dari ENV
GRADLE_PROPS="$ANDROID_DIR/gradle.properties"
touch "$GRADLE_PROPS"
if ! grep -q "ANDROID_KEYSTORE_PASSWORD" "$GRADLE_PROPS"; then
  cat >> "$GRADLE_PROPS" <<'EOF'

# === Autopatch signing via ENV ===
ANDROID_KEYSTORE_PATH=app/keystores/release.jks
ANDROID_KEYSTORE_PASSWORD=${ANDROID_KEYSTORE_PASSWORD}
ANDROID_KEY_ALIAS=${ANDROID_KEY_ALIAS}
ANDROID_KEY_PASSWORD=${ANDROID_KEY_PASSWORD}
EOF
  echo "[OK] gradle.properties ditambah setting signing (ENV)"
else
  echo "[SKIP] gradle.properties sudah ada rujukan signing"
fi

# 4) Patch app/build.gradle(.kts) untuk gunakan env signing jika belum ada
APP_KTS="$ANDROID_DIR/app/build.gradle.kts"
APP_GROOVY="$ANDROID_DIR/app/build.gradle"

if [ -f "$APP_KTS" ]; then
  # Inject signingConfigs jika tiada
  if ! grep -q "signingConfigs" "$APP_KTS"; then
    echo "==> Menambah signingConfigs (Kotlin DSL) ke app/build.gradle.kts"
    tmp="$APP_KTS.tmp"
    awk '1; /android\s*\{/ && !p { 
      print "    signingConfigs {";
      print "        create(\"release\") {";
      print "            storeFile = file(System.getenv(\"ANDROID_KEYSTORE_PATH\") ?: project.findProperty(\"ANDROID_KEYSTORE_PATH\") as String? ?: \"app/keystores/release.jks\")";
      print "            storePassword = System.getenv(\"ANDROID_KEYSTORE_PASSWORD\") ?: project.findProperty(\"ANDROID_KEYSTORE_PASSWORD\") as String?";
      print "            keyAlias = System.getenv(\"ANDROID_KEY_ALIAS\") ?: project.findProperty(\"ANDROID_KEY_ALIAS\") as String?";
      print "            keyPassword = System.getenv(\"ANDROID_KEY_PASSWORD\") ?: project.findProperty(\"ANDROID_KEY_PASSWORD\") as String?";
      print "        }";
      print "    }"; 
      p=1 
    }' "$APP_KTS" > "$tmp"
    mv "$tmp" "$APP_KTS"
    echo "[OK] signingConfigs ditambah (Kotlin DSL)"
  else
    echo "[SKIP] signingConfigs wujud"
  fi

  # Pastikan buildTypes.release guna signingConfig release
  if ! grep -q "buildTypes" "$APP_KTS"; then
    cat >> "$APP_KTS" <<'EOF'

android {
    buildTypes {
        getByName("release") {
            isMinifyEnabled = false
            signingConfig = signingConfigs.getByName("release")
        }
    }
}
EOF
    echo "[OK] buildTypes.release ditambah (Kotlin DSL)"
  else
    # Tambah signingConfig jika belum ada di dalam release
    if ! grep -q "signingConfig = signingConfigs.getByName(\"release\")" "$APP_KTS"; then
      sed -i.bak '/getByName("release")/a\ \ \ \ \ \ \ \ signingConfig = signingConfigs.getByName("release")' "$APP_KTS" || true
      echo "[OK] buildTypes.release now references signingConfigs.release"
    else
      echo "[SKIP] buildTypes.release sudah rujuk signingConfigs.release"
    fi
  fi

elif [ -f "$APP_GROOVY" ]; then
  # Groovy fallback (jarang perlu untuk projek anda, tapi disediakan)
  if ! grep -q "signingConfigs" "$APP_GROOVY"; then
    cat >> "$APP_GROOVY" <<'EOF'

android {
    signingConfigs {
        release {
            storeFile file(System.getenv("ANDROID_KEYSTORE_PATH") ?: project.findProperty("ANDROID_KEYSTORE_PATH") ?: "app/keystores/release.jks")
            storePassword System.getenv("ANDROID_KEYSTORE_PASSWORD") ?: project.findProperty("ANDROID_KEYSTORE_PASSWORD")
            keyAlias System.getenv("ANDROID_KEY_ALIAS") ?: project.findProperty("ANDROID_KEY_ALIAS")
            keyPassword System.getenv("ANDROID_KEY_PASSWORD") ?: project.findProperty("ANDROID_KEY_PASSWORD")
        }
    }
    buildTypes {
        release {
            minifyEnabled false
            signingConfig signingConfigs.release
        }
    }
}
EOF
    echo "[OK] signingConfigs + buildTypes.release ditambah (Groovy)"
  else
    echo "[SKIP] build.gradle (Groovy) sudah ada signingConfigs/buildTypes"
  fi
else
  echo "WARNING: Tiada app/build.gradle(.kts) — projek android tidak lengkap?"
fi

echo "===> Autopatch selesai."
echo "Nota:"
echo " - Untuk release signed, set ENV di Codemagic: ANDROID_KEYSTORE_BASE64, ANDROID_KEYSTORE_PASSWORD, ANDROID_KEY_ALIAS, ANDROID_KEY_PASSWORD"
echo " - Untuk debug cepat: gunakan workflow android_apk_debug (assembleDebug) tanpa signing."
