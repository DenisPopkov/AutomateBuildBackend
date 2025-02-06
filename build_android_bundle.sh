#!/bin/bash

source "/Users/denispopkov/PycharmProjects/AutomateBuildBackend/slack_upload.sh"

SECRET_FILE="/Users/denispopkov/Desktop/secret.txt"

# Validate secret.txt file existence
if [ ! -f "$SECRET_FILE" ]; then
  echo "Error: secret.txt file not found at $SECRET_FILE"
  exit 1
fi

# Read secret.txt for configuration values
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
BUMP_VERSION=$2

# Validate branch name input
if [ -z "$BRANCH_NAME" ]; then
  echo "Error: Branch name is required"
  exit 1
fi

open -a "Android Studio"

PROJECT_DIR="/Users/denispopkov/AndroidStudioProjects/SA_Neuro_Multiplatform"
cd "$PROJECT_DIR" || { echo "Project directory not found!"; exit 1; }

echo "Checking out branch: $BRANCH_NAME"
git fetch && git checkout "$BRANCH_NAME" && git pull origin "$BRANCH_NAME"

# Extract versionCode and versionName from build.gradle.kts
VERSION_CODE=$(grep "versionCode =" "$PROJECT_DIR/androidApp/build.gradle.kts" | awk -F '=' '{print $2}' | xargs)
VERSION_NAME=$(grep "versionName =" "$PROJECT_DIR/androidApp/build.gradle.kts" | awk -F '"' '{print $2}' | xargs)

if [ -z "$VERSION_CODE" ] || [ -z "$VERSION_NAME" ]; then
  echo "Error: Unable to extract versionCode or versionName from build.gradle.kts"
  exit 1
fi

OLD_VERSION=$VERSION_CODE

# Increment versionCode if required
if [ "$BUMP_VERSION" == "true" ]; then
  VERSION_CODE=$((VERSION_CODE + 1))
  sed -i '' "s/versionCode = $OLD_VERSION/versionCode = $VERSION_CODE/" "$PROJECT_DIR/androidApp/build.gradle.kts"
else
  echo "Nothing to bump"
fi

# Clean up old build artifacts
JNI_LIBS_PATH="$PROJECT_DIR/androidApp/src/main/jniLibs"
BUILD_PATH="$PROJECT_DIR/androidApp/build"
RELEASE_PATH="$PROJECT_DIR/androidApp/release"
rm -rf "$JNI_LIBS_PATH" "$BUILD_PATH" "$RELEASE_PATH"

# Build APK
./gradlew assembleRelease \
  -Pandroid.injected.signing.store.file="$KEYFILE" \
  -Pandroid.injected.signing.store.password="$KEY_PASSWORD" \
  -Pandroid.injected.signing.key.alias="$KEY_ALIAS" \
  -Pandroid.injected.signing.key.password="$KEY_PASSWORD"

APK_PATH="$PROJECT_DIR/androidApp/build/outputs/apk/release/androidApp-release.apk"
echo "path to APK = $APK_PATH"

if [ ! -f "$APK_PATH" ]; then
  execute_file_upload "${SLACK_BOT_TOKEN}" "${SLACK_CHANNEL}" "Android build failed :crycat:" "message"
  echo "Error: APK not found"
  exit 1
fi

echo "Building AAB (Android App Bundle)..."
./gradlew bundleRelease \
  -Pandroid.injected.signing.store.file="$KEYFILE" \
  -Pandroid.injected.signing.store.password="$KEY_PASSWORD" \
  -Pandroid.injected.signing.key.alias="$KEY_ALIAS" \
  -Pandroid.injected.signing.key.password="$KEY_PASSWORD"

AAB_PATH="$PROJECT_DIR/androidApp/build/outputs/bundle/release/androidApp-release.aab"

echo "Checking for built AAB..."
if [ ! -f "$AAB_PATH" ]; then
  execute_file_upload "${SLACK_BOT_TOKEN}" "${SLACK_CHANNEL}" "Android AAB build failed :crycat:" "message"
  echo "Error: AAB not found"
  exit 1
fi

echo "AAB built successfully: $AAB_PATH"

# Upload AAB to Slack
echo "Uploading AAB to Slack..."
execute_file_upload "${SLACK_BOT_TOKEN}" "${SLACK_CHANNEL}" "Android App Bundle from $BRANCH_NAME" "upload" "${AAB_PATH}"

if [ $? -eq 0 ]; then
  echo "AAB sent to Slack successfully."
  git fetch && git pull origin "$BRANCH_NAME"
  git add .
  git commit -m "Update hardcoded libs"
  git push origin "$BRANCH_NAME"
else
  execute_file_upload "${SLACK_BOT_TOKEN}" "${SLACK_CHANNEL}" "Android build failed :crycat:" "message"
  echo "Error sending AAB to Slack."
  exit 1
fi

if [ "$BUMP_VERSION" == "true" ]; then
  git fetch && git pull origin "$BRANCH_NAME"
  git add .
  git commit -m "Android version bump to $VERSION_CODE"
  git push origin "$BRANCH_NAME"

  echo "Version bump completed successfully. New versionCode: $VERSION_CODE"
else
  echo "Skipping version bump as bumpVersion is false."
fi
