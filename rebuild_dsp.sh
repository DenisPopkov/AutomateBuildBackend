#!/bin/bash

source "./slack_upload.sh"
source "./utils.sh"

SECRET_FILE="/c/Users/BlackBricks/Desktop/secret.txt"
PROJECT_DIR="/c/Users/BlackBricks/StudioProjects/SA_Neuro_Multiplatform"
CACHE_UPDATED_LIB_PATH="$PROJECT_DIR/desktopApp/resources/common/dsp/Debug/dspmac.dll"
HEROKU_PROD="/c/Users/BlackBricks/StudioProjects/neuro-production"
HEROKU_DEV="/c/Users/BlackBricks/StudioProjects/neuro-test"
HEROKU_LIBRARY="$HEROKU_PROD/files"
HEROKU_LIBRARY_DEV="$HEROKU_DEV/files"
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
IS_USE_DEV_ANALYTICS=$2

echo "isUseDevAnalytics param: $IS_USE_DEV_ANALYTICS"
if [[ "$IS_USE_DEV_ANALYTICS" == "true" ]]; then
  HEROKU_PATH="$HEROKU_PROD"
  HEROKU_LIBRARY_PATH="$HEROKU_LIBRARY"
  ENV="prod"
else
  HEROKU_PATH="$HEROKU_DEV"
  HEROKU_LIBRARY_PATH="$HEROKU_LIBRARY_DEV"
  ENV="dev"
fi

echo "Opening Android Studio..."
"/c/Program Files/Android/Android Studio/bin/studio64.exe" &

cd "$PROJECT_DIR" || { echo "Project directory not found!"; exit 1; }

sleep 5

echo "Checking out branch: $BRANCH_NAME"
git stash push -m "Pre-build stash"
git fetch --all
git checkout "$BRANCH_NAME"
git pull origin "$BRANCH_NAME" --no-rebase

message=":hammer_and_wrench: Start Windows DSP library update on \`$BRANCH_NAME\` for $ENV"
first_ts=$(post_message "${SLACK_BOT_TOKEN}" "${SLACK_CHANNEL}" "$message")

sleep 5

powershell -command "\
Add-Type -AssemblyName System.Windows.Forms; \
[System.Windows.Forms.SendKeys]::SendWait('^(+o)')"

sleep 80

if ! ./gradlew compileKotlin --stacktrace --info; then
  echo "Error: Gradle build failed"
  post_error_message "$BRANCH_NAME"
  exit 1
fi

cd "$HEROKU_PATH" || { echo "Heroku project directory not found!"; exit 1; }

sleep 5

git stash push -m "Pre-build stash"
git fetch heroku && git pull heroku "master" --no-rebase

rm -rf "$HEROKU_LIBRARY_PATH/dspmac.dll"

if [ -f "$CACHE_UPDATED_LIB_PATH" ]; then
  cp "$CACHE_UPDATED_LIB_PATH" "$HEROKU_LIBRARY_PATH"
else
  echo "Error: DSP library not found at $CACHE_UPDATED_LIB_PATH"
  post_error_message "$BRANCH_NAME"
  exit 1
fi

git add .
git commit -m "add: update DSP lib"
git push heroku "master"

message=":white_check_mark: Windows DSP library successfully updated on \`$BRANCH_NAME\` for $ENV"
execute_file_upload "${SLACK_BOT_TOKEN}" "${SLACK_CHANNEL}" "$message" "upload" "${CACHE_UPDATED_LIB_PATH}"
delete_message "${SLACK_BOT_TOKEN}" "${SLACK_CHANNEL}" "$first_ts"