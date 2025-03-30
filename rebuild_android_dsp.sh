#!/bin/bash

source "/Users/denispopkov/PycharmProjects/AutomateBuildBackend/slack_upload.sh"
source "/Users/denispopkov/PycharmProjects/AutomateBuildBackend/utils.sh"

PROJECT_DIR="/Users/denispopkov/AndroidStudioProjects/SA_Neuro_Multiplatform"
SECRET_FILE="/Users/denispopkov/Desktop/secret.txt"
ERROR_LOG_FILE="/tmp/build_error_log.txt"
JNI_LIBS_PATH="$PROJECT_DIR/androidApp/src/main/jniLibs"
BUILD_PATH="$PROJECT_DIR/androidApp/build"
RELEASE_PATH="$PROJECT_DIR/androidApp/release"

post_error_message() {
  local branch_name=$1
  local message=":x: Failed to update DSP library on \`$branch_name\`"
  execute_file_upload "${SLACK_BOT_TOKEN}" "${SLACK_CHANNEL}" "$message" "upload" "$ERROR_LOG_FILE"
}

while IFS='=' read -r key value; do
  key=$(echo "$key" | xargs)
  value=$(echo "$value" | xargs)

  case "$key" in
    "SLACK_BOT_TOKEN") SLACK_BOT_TOKEN="$value" ;;
    "SLACK_CHANNEL") SLACK_CHANNEL="$value" ;;
    "KEYFILE") KEYFILE="$value" ;;
    "KEY_ALIAS") KEY_ALIAS="$value" ;;
    "KEY_PASSWORD") KEY_PASSWORD="$value" ;;
  esac
done < "$SECRET_FILE"

BRANCH_NAME=$1

open -a "Android Studio"

cd "$PROJECT_DIR" || { echo "Project directory not found!"; exit 1; }

echo "Checking out branch: $BRANCH_NAME"
git stash push -m "Pre-build stash"
git fetch && git checkout "$BRANCH_NAME" && git pull origin "$BRANCH_NAME" --no-rebase

ANDROID_BUILD_FILE="$PROJECT_DIR/androidApp/build.gradle.kts"

rm -f "$ALL_BUILD_FILE"
cp "$ANDROID_BUILD_FILE" "$ALL_BUILD_FILE"

echo "Replacing $ANDROID_BUILD_FILE with $ARM_BUILD_FILE"
rm -f "$ANDROID_BUILD_FILE"
cp "$ARM_BUILD_FILE" "$ANDROID_BUILD_FILE"

JNI_LIBS_PATH="$PROJECT_DIR/androidApp/src/main/jniLibs"
BUILD_PATH="$PROJECT_DIR/androidApp/build"
RELEASE_PATH="$PROJECT_DIR/androidApp/release"

rm -rf "$JNI_LIBS_PATH"
rm -rf "$BUILD_PATH"
rm -rf "$RELEASE_PATH"

./gradlew assembleRelease \
  -Pandroid.injected.signing.store.file="$KEYFILE" \
  -Pandroid.injected.signing.store.password="$KEY_PASSWORD" \
  -Pandroid.injected.signing.key.alias="$KEY_ALIAS" \
  -Pandroid.injected.signing.key.password="$KEY_PASSWORD"

APK_PATH="$PROJECT_DIR/androidApp/build/outputs/apk/release/androidApp-release.apk"
echo "path to APK = $APK_PATH"

if [ ! -f "$APK_PATH" ]; then
  post_error_message "$BRANCH_NAME"
  echo "Error: APK not found"
  exit 1
fi

APK_ZIP_PATH="${APK_PATH%.apk}.zip"
mv "$APK_PATH" "$APK_ZIP_PATH"

unzip -o "$APK_ZIP_PATH" -d "$PROJECT_DIR/androidApp/build/outputs/apk/release/"

mkdir -p "$JNI_LIBS_PATH/arm64-v8a" "$JNI_LIBS_PATH/x86_64"
cp "$PROJECT_DIR/androidApp/build/outputs/apk/release/lib/arm64-v8a/libdspandroid.so" "$JNI_LIBS_PATH/x86_64/"
cp "$PROJECT_DIR/androidApp/build/outputs/apk/release/lib/arm64-v8a/libdspandroid.so" "$JNI_LIBS_PATH/arm64-v8a/"

rm -rf "$BUILD_PATH"
rm -rf "$RELEASE_PATH"
