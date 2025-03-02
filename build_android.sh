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
isBundleToBuild=$3
isUseDevAnalytics=$4

# Validate branch name input
if [ -z "$BRANCH_NAME" ]; then
  echo "Error: Branch name is required"
  exit 1
fi

open -a "Android Studio"

end_time=$(TZ=Asia/Omsk date -v+15M "+%H:%M")
message="Android build started. It will be ready approximately at $end_time Omsk Time."
execute_file_upload "${SLACK_BOT_TOKEN}" "${SLACK_CHANNEL}" "$message" "message"

PROJECT_DIR="/Users/denispopkov/AndroidStudioProjects/SA_Neuro_Multiplatform"
cd "$PROJECT_DIR" || { echo "Project directory not found!"; exit 1; }

echo "Checking out branch: $BRANCH_NAME"
git stash push -m "Pre-build stash"
git fetch && git checkout "$BRANCH_NAME" && git pull origin "$BRANCH_NAME" --no-rebase

# Replace build.gradle.kts for Android with arm_target/build.gradle.kts
ANDROID_BUILD_FILE="$PROJECT_DIR/androidApp/build.gradle.kts"
ARM_BUILD_FILE="/Users/denispopkov/Desktop/arm_target/build.gradle.kts"
ALL_BUILD_FILE="/Users/denispopkov/Desktop/all_target/build.gradle.kts"

# For dev analytics
SHARED_GRADLE_FILE="$PROJECT_DIR/shared/build.gradle.kts"
PROD_SHARED_GRADLE_FILE="/Users/denispopkov/Desktop/prod/build.gradle.kts"

# Extract versionCode and versionName from build.gradle.kts
VERSION_CODE=$(grep "versionCode =" "$PROJECT_DIR/androidApp/build.gradle.kts" | awk -F '=' '{print $2}' | xargs)
VERSION_NAME=$(grep "versionName =" "$PROJECT_DIR/androidApp/build.gradle.kts" | awk -F '"' '{print $2}' | xargs)

if [ -z "$VERSION_CODE" ] || [ -z "$VERSION_NAME" ]; then
  echo "Error: Unable to extract versionCode or versionName from build.gradle.kts"
  exit 1
fi

OLD_VERSION=$VERSION_CODE

if [ "$BUMP_VERSION" == "true" ]; then
  VERSION_CODE=$((VERSION_CODE + 1))
  sed -i '' "s/versionCode = $OLD_VERSION/versionCode = $VERSION_CODE/" "$PROJECT_DIR/androidApp/build.gradle.kts"
  git pull origin "$BRANCH_NAME" --no-rebase
  git add .
  git commit -m "Android version bump to $VERSION_CODE"
  git push origin "$BRANCH_NAME"
else
  echo "Nothing to bump"
fi

if [ "$isUseDevAnalytics" == "false" ]; then
  echo "Replacing $SHARED_GRADLE_FILE with $PROD_SHARED_GRADLE_FILE"
  rm -f "$SHARED_GRADLE_FILE"
  cp "$PROD_SHARED_GRADLE_FILE" "$SHARED_GRADLE_FILE"

  open -a "Android Studio"

  sleep 5

  osascript -e '
  tell application "System Events"
    tell process "Android Studio"
        keystroke "O" using {command down, shift down}
    end tell
  end tell
  '

  sleep 80
  else
    echo "Nothing to change with analytics"
fi

rm -f "$ALL_BUILD_FILE"
cp "$ANDROID_BUILD_FILE" "$ALL_BUILD_FILE"

echo "Replacing $ANDROID_BUILD_FILE with $ARM_BUILD_FILE"
rm -f "$ANDROID_BUILD_FILE"
cp "$ARM_BUILD_FILE" "$ANDROID_BUILD_FILE"

# Clean up old jniLibs
JNI_LIBS_PATH="$PROJECT_DIR/androidApp/src/main/jniLibs"
BUILD_PATH="$PROJECT_DIR/androidApp/build"
RELEASE_PATH="$PROJECT_DIR/androidApp/release"

rm -rf "$JNI_LIBS_PATH"
rm -rf "$BUILD_PATH"
rm -rf "$RELEASE_PATH"

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

# Rename the APK to .zip (no zipping necessary)
APK_ZIP_PATH="${APK_PATH%.apk}.zip"
mv "$APK_PATH" "$APK_ZIP_PATH"

# Unzip the APK (which is a zip file) directly
unzip -o "$APK_ZIP_PATH" -d "$PROJECT_DIR/androidApp/build/outputs/apk/release/"

# Copy libraries to jniLibs
mkdir -p "$JNI_LIBS_PATH/arm64-v8a" "$JNI_LIBS_PATH/x86_64"
cp "$PROJECT_DIR/androidApp/build/outputs/apk/release/lib/arm64-v8a/libdspandroid.so" "$JNI_LIBS_PATH/x86_64/"
cp "$PROJECT_DIR/androidApp/build/outputs/apk/release/lib/arm64-v8a/libdspandroid.so" "$JNI_LIBS_PATH/arm64-v8a/"

# Cleanup after the build
rm -rf "$BUILD_PATH"
rm -rf "$RELEASE_PATH"

rm -f "$ANDROID_BUILD_FILE"
cp "$ALL_BUILD_FILE" "$ANDROID_BUILD_FILE"

if [ "$isBundleToBuild" == "true" ]; then
  echo "Building AAB (Android App Bundle)..."

  # Build AAB
  ./gradlew bundleRelease \
    -Pandroid.injected.signing.store.file="$KEYFILE" \
    -Pandroid.injected.signing.store.password="$KEY_PASSWORD" \
    -Pandroid.injected.signing.key.alias="$KEY_ALIAS" \
    -Pandroid.injected.signing.key.password="$KEY_PASSWORD"

  AAB_PATH="$PROJECT_DIR/androidApp/build/outputs/bundle/release/androidApp-release.aab"

  if [ ! -f "$AAB_PATH" ]; then
    execute_file_upload "${SLACK_BOT_TOKEN}" "${SLACK_CHANNEL}" "Android build failed :crycat:" "message"
    echo "Error: Signed APK not found at expected path: $AAB_PATH"
    exit 1
  fi

  echo "APK built successfully: $AAB_PATH"

  # Rename APK with unique name if needed
  BASE_NAME="neuro3-${VERSION_NAME}-[${VERSION_CODE}].aab"
  FINAL_DIR="/Users/denispopkov/Desktop/builds"
  FINAL_AAB_PATH="$FINAL_DIR/$BASE_NAME"

  # Ensure unique filename in the builds folder
  INDEX=1
  while [ -f "$FINAL_AAB_PATH" ]; do
    FINAL_AAB_PATH="$FINAL_DIR/neuro3-${VERSION_NAME}-[${VERSION_CODE}]_${INDEX}.aab"
    INDEX=$((INDEX + 1))
  done

  # Move the APK file to the builds folder with the unique name
  mv "$APK_PATH" "$FINAL_AAB_PATH" || { echo "Error renaming AAB"; exit 1; }
  echo "APK renamed and moved to: $FINAL_AAB_PATH"

  FILE_PATH="$FINAL_AAB_PATH"

  # Upload AAB to Slack
  echo "Uploading AAB to Slack..."
  execute_file_upload "${SLACK_BOT_TOKEN}" "${SLACK_CHANNEL}" "Android App Bundle from $BRANCH_NAME" "upload" "${FINAL_AAB_PATH}"

  sleep 20

  if [ $? -eq 0 ]; then
    echo "AAB sent to Slack successfully."
    git pull origin "$BRANCH_NAME" --no-rebase
    git stash push -m "Stashing build.gradle.kts" --keep-index -- "$PROJECT_DIR/shared/build.gradle.kts"
    git add .
    git commit -m "Update hardcoded libs"
    git push origin "$BRANCH_NAME" --no-rebase
  else
    echo "Error sending AAB to Slack."
    exit 1
  fi

else
  # If not building AAB, then build APK
  echo "Building APK..."

  # Build APK
  ./gradlew assembleRelease \
    -Pandroid.injected.signing.store.file="$KEYFILE" \
    -Pandroid.injected.signing.store.password="$KEY_PASSWORD" \
    -Pandroid.injected.signing.key.alias="$KEY_ALIAS" \
    -Pandroid.injected.signing.key.password="$KEY_PASSWORD"

  # Find the signed APK
  APK_PATH="$PROJECT_DIR/androidApp/build/outputs/apk/release/androidApp-release.apk"

  if [ ! -f "$APK_PATH" ]; then
    execute_file_upload "${SLACK_BOT_TOKEN}" "${SLACK_CHANNEL}" "Android build failed :crycat:" "message"
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
  execute_file_upload "${SLACK_BOT_TOKEN}" "${SLACK_CHANNEL}" "Android APK from $BRANCH_NAME" "upload" "${FILE_PATH}"

  if [ $? -eq 0 ]; then
    echo "APK sent to Slack successfully."
    git pull origin "$BRANCH_NAME" --no-rebase
    git stash push -m "Stashing build.gradle.kts" --keep-index -- "$PROJECT_DIR/shared/build.gradle.kts"
    git add .
    git commit -m "Update hardcoded libs"
    git push origin "$BRANCH_NAME"
  else
    echo "Error sending APK to Slack."
    exit 1
  fi
fi
