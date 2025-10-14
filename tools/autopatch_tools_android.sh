#!/usr/bin/env bash
set -euo pipefail

echo "===> Autopatch: kawinkan tools/ dengan android/ (Free Plan)"

ROOT="$(pwd)"
ANDROID_DIR="$ROOT/android"

if [ ! -d "$ANDROID_DIR" ]; then
  echo "ERROR: Folder android/ tiada. Jika Expo managed, jalankan:"
  echo "  npx expo prebuild --platform android"
  exit 1
fi

chmod +x "$ANDROID_DIR/gradlew" || true

# Decode keystore dari ENV (kalau ada)
if [ -n "${ANDROID_KEYSTORE_BASE64:-}" ]; then
  mkdir -p "$ANDROID_DIR/app/keystores"
  echo "$ANDROID_KEYSTORE_BASE64" | base64 -d > "$ANDROID_DIR/app/keystores/release.jks"
  echo "[OK] Keystore ditulis ke android/app/keystores/release.jks"
fi

# Tambah rujukan signing ke gradle.properties
GRADLE_PROPS="$ANDROID_DIR/gradle.properties"
touch "$GRADLE_PROPS"
if ! grep -q "ANDROID_KEYSTORE_PASSWORD" "$GRADLE_PROPS"; then
  cat >> "$GRADLE_PROPS" <<'EOF'

# === Autopatch signing via ENV (Free Plan) ===
ANDROID_KEYSTORE_PATH=app/keystores/release.jks
ANDROID_KEYSTORE_PASSWORD=${ANDROID_KEYSTORE_PASSWORD}
ANDROID_KEY_ALIAS=${ANDROID_KEY_ALIAS}
ANDROID_KEY_PASSWORD=${ANDROID_KEY_PASSWORD}
EOF
  echo "[OK] gradle.properties updated with signing env vars"
else
  echo "[SKIP] gradle.properties already has signing info"
fi

APP_KTS="$ANDROID_DIR/app/build.gradle.kts"
if [ -f "$APP_KTS" ]; then
  if ! grep -q "signingConfigs" "$APP_KTS"; then
    echo "[+] Menambah signingConfigs (Kotlin DSL)"
    tmp="$APP_KTS.tmp"
    awk '1; /android\s*\{/ && !p { 
      print "    signingConfigs {";
      print "        create(\"release\") {";
      print "            storeFile = file(System.getenv(\"ANDROID_KEYSTORE_PATH\") ?: \"app/keystores/release.jks\")";
      print "            storePassword = System.getenv(\"ANDROID_KEYSTORE_PASSWORD\")";
      print "            keyAlias = System.getenv(\"ANDROID_KEY_ALIAS\")";
      print "            keyPassword = System.getenv(\"ANDROID_KEY_PASSWORD\")";
      print "        }";
      print "    }"; p=1 }' "$APP_KTS" > "$tmp"
    mv "$tmp" "$APP_KTS"
  fi
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
  fi
fi

echo "===> Autopatch selesai (Free Plan)."
