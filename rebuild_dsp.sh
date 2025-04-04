#!/bin/bash

source "/Users/denispopkov/PycharmProjects/AutomateBuildBackend/slack_upload.sh"
source "/Users/denispopkov/PycharmProjects/AutomateBuildBackend/utils.sh"

PROJECT_DIR="/Users/denispopkov/AndroidStudioProjects/SA_Neuro_Multiplatform"
SECRET_FILE="/Users/denispopkov/Desktop/secret.txt"
SET_UPDATED_LIB_PATH="$PROJECT_DIR/shared/src/commonMain/resources/MR/files/libdspmac.dylib"
CACHE_UPDATED_LIB_PATH="$PROJECT_DIR/desktopApp/build/native/libdspmac.dylib"
ERROR_LOG_FILE="/tmp/build_error_log.txt"

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
    "TEAM_ID") TEAM_ID="$value" ;;
    "APPLE_ID") APPLE_ID="$value" ;;
    "NOTARY_PASSWORD") NOTARY_PASSWORD="$value" ;;
    "USER_PASSWORD") USER_PASSWORD="$value" ;;
  esac
done < "$SECRET_FILE"

if [ -z "$TEAM_ID" ] || [ -z "$APPLE_ID" ] || [ -z "$NOTARY_PASSWORD" ] || [ -z "$USER_PASSWORD" ]; then
  echo "Error: TEAM_ID, APPLE_ID, NOTARY_PASSWORD, or USER_PASSWORD is missing in $SECRET_FILE"
  post_error_message "$BRANCH_NAME"
  exit 1
fi

BRANCH_NAME=$1

echo "Checking out branch: $BRANCH_NAME"
git stash push -m "Pre-build stash"
git fetch && git checkout "$BRANCH_NAME" && git pull origin "$BRANCH_NAME" --no-rebase

message=":hammer_and_wrench: Start Desktop DSP library update on \`$BRANCH_NAME\`"
post_message "${SLACK_BOT_TOKEN}" "${SLACK_CHANNEL}" "$message"

echo "Opening Android Studio..."
open -a "Android Studio"

PROJECT_DIR="/Users/denispopkov/AndroidStudioProjects/SA_Neuro_Multiplatform"
cd "$PROJECT_DIR" || { echo "Project directory not found!"; exit 1; }

enable_dsp_gradle_task

sleep 5

osascript -e '
  tell application "System Events"
    tell process "Android Studio"
        keystroke "O" using {command down, shift down}
    end tell
  end tell
'

sleep 80

if ! ./gradlew compileKotlin --stacktrace --info; then
  echo "Error: Gradle build failed"
  post_error_message "$BRANCH_NAME"
  disable_dsp_gradle_task
  exit 1
fi

sleep 5

disable_dsp_gradle_task

rm -f "$SET_UPDATED_LIB_PATH"
cp "$CACHE_UPDATED_LIB_PATH" "$SET_UPDATED_LIB_PATH"

sleep 10

git add .
git commit -m "add: update dsp lib"
git push origin "$BRANCH_NAME"

message=":white_check_mark: DSP library successfully updated on \`$BRANCH_NAME\`"
execute_file_upload "${SLACK_BOT_TOKEN}" "${SLACK_CHANNEL}" "$message" "upload" "${SET_UPDATED_LIB_PATH}"
