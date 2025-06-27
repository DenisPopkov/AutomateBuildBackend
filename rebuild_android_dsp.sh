#!/bin/bash

source "/Users/denispopkov/PycharmProjects/AutomateBuildBackend/slack_upload.sh"
source "/Users/denispopkov/PycharmProjects/AutomateBuildBackend/utils.sh"

PROJECT_DIR="/Users/denispopkov/AndroidStudioProjects/SA_Neuro_Multiplatform"
HEROKU_PROD="/Users/denispopkov/AndroidStudioProjects/neuro-production/"
HEROKU_DEV="/Users/denispopkov/AndroidStudioProjects/neuro-test/"
HEROKU_LIBRARY="/Users/denispopkov/AndroidStudioProjects/neuro-production/files/"
HEROKU_LIBRARY_DEV="/Users/denispopkov/AndroidStudioProjects/neuro-test/files/"
SECRET_FILE="/Users/denispopkov/Desktop/secret.txt"
ERROR_LOG_FILE="/tmp/build_error_log.txt"
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
IS_USE_DEV_ANALYTICS=$2

echo "isUseDevAnalytics param: $IS_USE_DEV_ANALYTICS"
if [[ "$IS_USE_DEV_ANALYTICS" == "true" ]]; then
  HEROKU_PATH="$HEROKU_PROD"
  HEROKU_LIBRARY_PATH="$HEROKU_LIBRARY"
else
  HEROKU_PATH="$HEROKU_DEV"
  HEROKU_LIBRARY_PATH="$HEROKU_LIBRARY_DEV"
fi

message=":hammer_and_wrench: Start Android DSP library update on \`$BRANCH_NAME\`"
first_ts=$(post_message "${SLACK_BOT_TOKEN}" "${SLACK_CHANNEL}" "$message")

open -a "Android Studio"

cd "$PROJECT_DIR" || { echo "Project directory not found!"; exit 1; }

echo "Checking out branch: $BRANCH_NAME"
git stash push -m "Pre-build stash"
git fetch && git checkout "$BRANCH_NAME" && git pull origin "$BRANCH_NAME" --no-rebase

BUILD_PATH="$PROJECT_DIR/androidApp/build"
RELEASE_PATH="$PROJECT_DIR/androidApp/release"

rm -rf "$BUILD_PATH"
rm -rf "$RELEASE_PATH"

uncomment_android_dsp_gradle_task

sleep 5

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

if ! unzip -o "$APK_ZIP_PATH" -d "$PROJECT_DIR/androidApp/build/outputs/apk/release/"; then
  echo "Error: Failed to unzip APK" >> "$ERROR_LOG_FILE"
  post_error_message "$BRANCH_NAME"
  exit 1
fi

comment_android_dsp_gradle_task

sleep 5

cd "$HEROKU_PATH" || { echo "Project directory not found!"; exit 1; }

sleep 5

git stash push -m "Pre-build stash"
git fetch && git pull origin "master" --no-rebase

rm -rf "$HEROKU_LIBRARY_PATH/libdspandroid.so"
cp "$PROJECT_DIR/androidApp/build/outputs/apk/release/lib/arm64-v8a/libdspandroid.so" "$HEROKU_LIBRARY_PATH"

git add .
git commit -m "add: update dsp lib"
git push origin "master"

rm -rf "$BUILD_PATH"
rm -rf "$RELEASE_PATH"

message=":white_check_mark: DSP library successfully updated on \`$BRANCH_NAME\`"
execute_file_upload "${SLACK_BOT_TOKEN}" "${SLACK_CHANNEL}" "$message" "upload" "$PROJECT_DIR/androidApp/build/outputs/apk/release/lib/arm64-v8a/libdspandroid.so"
delete_message "${SLACK_BOT_TOKEN}" "${SLACK_CHANNEL}" "$first_ts"
