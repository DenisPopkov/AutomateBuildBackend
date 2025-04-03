#!/bin/bash

source "./slack_upload.sh"
source "./utils.sh"

SECRET_FILE="/c/Users/BlackBricks/Desktop/secret.txt"
PROJECT_DIR="/c/Users/BlackBricks/StudioProjects/SA_Neuro_Multiplatform"
SET_UPDATED_LIB_PATH="$PROJECT_DIR/shared/src/commonMain/resources/MR/files/libs/dspmac.dll"
CACHE_UPDATED_LIB_PATH="$PROJECT_DIR/desktopApp/resources/common/dsp/Debug/dspmac.dll"
ERROR_LOG_FILE="${ERROR_LOG_FILE:-/tmp/build_error_log.txt}"

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

echo "Opening Android Studio..."
"/c/Program Files/Android/Android Studio/bin/studio64.exe" &

cd "$PROJECT_DIR" || { echo "Project directory not found!"; exit 1; }

echo "Checking out branch: $BRANCH_NAME"
git stash push -m "Pre-build stash"
git fetch && git checkout "$BRANCH_NAME" && git pull origin "$BRANCH_NAME" --no-rebase

message=":hammer_and_wrench: Start Desktop DSP library update on \`$BRANCH_NAME\`"
post_message "${SLACK_BOT_TOKEN}" "${SLACK_CHANNEL}" "$message"

enable_dsp_gradle_task

sleep 5

powershell -command "\
Add-Type -AssemblyName System.Windows.Forms; \
[System.Windows.Forms.SendKeys]::SendWait('^(+o)'); \
Start-Sleep -Milliseconds 100"

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

git stash push -m "Pre-build stash"
git fetch --prune origin
git checkout -b "$BRANCH_NAME" "origin/$BRANCH_NAME"
git pull origin "$BRANCH_NAME" --no-rebase

message=":white_check_mark: DSP library successfully updated on \`$BRANCH_NAME\`"
execute_file_upload "${SLACK_BOT_TOKEN}" "${SLACK_CHANNEL}" "$message" "upload" "${SET_UPDATED_LIB_PATH}"
