#!/bin/bash

source "/Users/denispopkov/PycharmProjects/AutomateBuildBackend/slack_upload.sh"

SECRET_FILE="/Users/denispopkov/Desktop/secret.txt"

if [ ! -f "$SECRET_FILE" ]; then
  echo "Error: secret.txt file not found at $SECRET_FILE"
  exit 1
fi

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

if [ -z "$BRANCH_NAME" ]; then
  echo "Error: Branch name is required"
  exit 1
fi

open -a "Android Studio"

PROJECT_DIR="/Users/denispopkov/AndroidStudioProjects/SA_Neuro_Multiplatform"
cd "$PROJECT_DIR" || { echo "Project directory not found!"; exit 1; }

echo "Checking out branch: $BRANCH_NAME"
git fetch && git checkout "$BRANCH_NAME" && git pull origin "$BRANCH_NAME"

# Extract versionCode and versionName
VERSION_CODE=$(grep "versionCode =" "$PROJECT_DIR/androidApp/build.gradle.kts" | awk -F '=' '{print $2}' | xargs)
VERSION_NAME=$(grep "versionName =" "$PROJECT_DIR/androidApp/build.gradle.kts" | awk -F '"' '{print $2}' | xargs)

OLD_VERSION=$VERSION_CODE

if [ -z "$VERSION_CODE" ] || [ -z "$VERSION_NAME" ]; then
  echo "Error: Unable to extract versionCode or versionName from build.gradle.kts"
  exit 1
fi

if [ "$BUMP_VERSION" == "true" ]; then
  VERSION_CODE=$((VERSION_CODE + 1))
  sed -i '' "s/versionCode = $OLD_VERSION/versionCode = $VERSION_CODE/" "$PROJECT_DIR/androidApp/build.gradle.kts"
else
  echo "Nothing to bump"
fi

# Build Signed APK
echo "Building signed APK..."
./gradlew assembleRelease \
  -Pandroid.injected.signing.store.file="$KEYFILE" \
  -Pandroid.injected.signing.store.password="$KEY_PASSWORD" \
  -Pandroid.injected.signing.key.alias="$KEY_ALIAS" \
  -Pandroid.injected.signing.key.password="$KEY_PASSWORD"

# Find the signed APK
APK_PATH="$PROJECT_DIR/androidApp/build/outputs/apk/release/androidApp-release.apk"

if [ ! -f "$APK_PATH" ]; then
  execute_file_upload "${SLACK_BOT_TOKEN}" "${SLACK_CHANNEL}" "Android build failed :crycat: - signed APK not found at expected path: $APK_PATH" "message"
  echo "Error: Signed APK not found at expected path: $APK_PATH"
  exit 1
fi

echo "APK built successfully: $APK_PATH"

# Rename APK with unique name if needed
BASE_NAME="neuro3-${VERSION_NAME}-[${VERSION_CODE}].apk"
FINAL_DIR="/Users/denispopkov/Desktop/builds"
FINAL_APK_PATH="$FINAL_DIR/$BASE_NAME"

# Ensure unique filename in the builds folder
INDEX=1
while [ -f "$FINAL_APK_PATH" ]; do
    FINAL_APK_PATH="$FINAL_DIR/neuro3-${VERSION_NAME}-[${VERSION_CODE}]_${INDEX}.apk"
    INDEX=$((INDEX + 1))
done

# Move the APK file to the builds folder with the unique name
mv "$APK_PATH" "$FINAL_APK_PATH" || { echo "Error renaming APK"; exit 1; }
echo "APK renamed and moved to: $FINAL_APK_PATH"

FILE_PATH="$FINAL_APK_PATH"

# Upload APK to Slack
echo "Uploading APK to Slack..."
execute_file_upload "${SLACK_BOT_TOKEN}" "${SLACK_CHANNEL}" "Android from $BRANCH_NAME" "upload" "${FILE_PATH}"

if [ $? -eq 0 ]; then
    echo "APK sent to Slack successfully."
else
    echo "Error sending APK to Slack."
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
