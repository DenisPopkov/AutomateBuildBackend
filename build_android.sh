#!/bin/bash

source "/Users/denispopkov/PycharmProjects/AutomateBuildBackend/slack_upload.sh"
source "/Users/denispopkov/PycharmProjects/AutomateBuildBackend/utils.sh"

SECRET_FILE="/Users/denispopkov/Desktop/secret.txt"
ERROR_LOG_FILE="/tmp/build_error_log.txt"

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
isUseDevAnalytics=$2

post_error_message() {
  local branch_name=$1
  local message=":x: Failed to build Android on \`$branch_name\`"
  execute_file_upload "${SLACK_BOT_TOKEN}" "${SLACK_CHANNEL}" "$message" "upload" "$ERROR_LOG_FILE"
}

open -a "Android Studio"

analyticsMessage=""

if [ "$isUseDevAnalytics" == "true" ]; then
  analyticsMessage="dev"
else
  analyticsMessage="prod"
fi

end_time=$(TZ=Asia/Omsk date -v+15M "+%H:%M")
message=":hammer_and_wrench: Android build started on \`$BRANCH_NAME\`
:mag_right: Analytics look on $analyticsMessage
:clock2: It will be ready approximately at $end_time"
post_message "${SLACK_BOT_TOKEN}" "${SLACK_CHANNEL}" "$message"

PROJECT_DIR="/Users/denispopkov/AndroidStudioProjects/SA_Neuro_Multiplatform"
cd "$PROJECT_DIR" || { echo "Project directory not found!"; exit 1; }

echo "Checking out branch: $BRANCH_NAME"
git stash push -m "Pre-build stash"
git fetch && git checkout "$BRANCH_NAME" && git pull origin "$BRANCH_NAME" --no-rebase

# Extract versionCode and versionName from build.gradle.kts
VERSION_CODE=$(grep "versionCode =" "$PROJECT_DIR/androidApp/build.gradle.kts" | awk -F '=' '{print $2}' | xargs)
VERSION_NAME=$(grep "versionName =" "$PROJECT_DIR/androidApp/build.gradle.kts" | awk -F '"' '{print $2}' | xargs)

OLD_VERSION=$VERSION_CODE

VERSION_CODE=$((VERSION_CODE + 1))
sed -i '' "s/versionCode = $OLD_VERSION/versionCode = $VERSION_CODE/" "$PROJECT_DIR/androidApp/build.gradle.kts"
git pull origin "$BRANCH_NAME" --no-rebase
git add .
git commit -m "Android version bump to $VERSION_CODE"
git push origin "$BRANCH_NAME"

if [ "$isUseDevAnalytics" == "false" ]; then
  enable_prod_keys

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

if [ "$isUseDevAnalytics" == "false" ]; then
  echo "Building AAB (Android App Bundle)..."

  # Build AAB
  ./gradlew bundleRelease \
    -Pandroid.injected.signing.store.file="$KEYFILE" \
    -Pandroid.injected.signing.store.password="$KEY_PASSWORD" \
    -Pandroid.injected.signing.key.alias="$KEY_ALIAS" \
    -Pandroid.injected.signing.key.password="$KEY_PASSWORD"

  AAB_PATH="$PROJECT_DIR/androidApp/build/outputs/bundle/release/androidApp-release.aab"

  if [ ! -f "$AAB_PATH" ]; then
    post_error_message "$BRANCH_NAME"
    echo "Error: Signed AAB not found at expected path: $AAB_PATH"
    exit 1
  fi

  # Rename AAB with version info
  NEW_AAB_BASE="neuro3-${VERSION_NAME}-[${VERSION_CODE}].aab"
  NEW_AAB_PATH="$PROJECT_DIR/androidApp/build/outputs/bundle/release/${NEW_AAB_BASE}"

  INDEX=1
  while [ -f "$NEW_AAB_PATH" ]; do
    NEW_AAB_BASE="neuro3-${VERSION_NAME}-[${VERSION_CODE}]_${INDEX}.aab"
    NEW_AAB_PATH="$PROJECT_DIR/androidApp/build/outputs/bundle/release/${NEW_AAB_BASE}"
    INDEX=$((INDEX + 1))
  done

  mv "$AAB_PATH" "$NEW_AAB_PATH" || { echo "Error renaming AAB"; exit 1; }
  echo "AAB renamed to: $NEW_AAB_PATH"

  FILE_PATH="$NEW_AAB_PATH"

  # Upload AAB to Slack
  echo "Uploading AAB to Slack..."
  execute_file_upload "${SLACK_BOT_TOKEN}" "${SLACK_CHANNEL}" "Android App Bundle from $BRANCH_NAME" "upload" "${FILE_PATH}"

  sleep 20

  undo_enable_prod_keys

  if [ $? -eq 0 ]; then
    echo "AAB sent to Slack successfully."
    git pull origin "$BRANCH_NAME" --no-rebase
    git add .
    git commit -m "Update hardcoded libs"
    git push origin "$BRANCH_NAME"
  else
    echo "Error sending AAB to Slack."
    post_error_message "$BRANCH_NAME"
    exit 1
  fi

else
  # Build APK
  echo "Building APK..."

  ./gradlew assembleRelease \
    -Pandroid.injected.signing.store.file="$KEYFILE" \
    -Pandroid.injected.signing.store.password="$KEY_PASSWORD" \
    -Pandroid.injected.signing.key.alias="$KEY_ALIAS" \
    -Pandroid.injected.signing.key.password="$KEY_PASSWORD"

  APK_PATH="$PROJECT_DIR/androidApp/build/outputs/apk/release/androidApp-release.apk"

  if [ ! -f "$APK_PATH" ]; then
    post_error_message "$BRANCH_NAME"
    echo "Error: Signed APK not found at expected path: $APK_PATH"
    exit 1
  fi

  # Rename APK with version info
  NEW_APK_BASE="neuro3-${VERSION_NAME}-[${VERSION_CODE}].apk"
  NEW_APK_PATH="$PROJECT_DIR/androidApp/build/outputs/apk/release/${NEW_APK_BASE}"

  INDEX=1
  while [ -f "$NEW_APK_PATH" ]; do
    NEW_APK_BASE="neuro3-${VERSION_NAME}-[${VERSION_CODE}]_${INDEX}.apk"
    NEW_APK_PATH="$PROJECT_DIR/androidApp/build/outputs/apk/release/${NEW_APK_BASE}"
    INDEX=$((INDEX + 1))
  done

  mv "$APK_PATH" "$NEW_APK_PATH" || { echo "Error renaming APK"; exit 1; }
  echo "APK renamed to: $NEW_APK_PATH"

  FILE_PATH="$NEW_APK_PATH"

  # Upload APK to Slack
  echo "Uploading APK to Slack..."
  execute_file_upload "${SLACK_BOT_TOKEN}" "${SLACK_CHANNEL}" "Android APK from $BRANCH_NAME" "upload" "${FILE_PATH}"

  undo_enable_prod_keys
fi