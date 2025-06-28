#!/bin/bash

source "/Users/denispopkov/PycharmProjects/AutomateBuildBackend/slack_upload.sh"
source "/Users/denispopkov/PycharmProjects/AutomateBuildBackend/utils.sh"

PROJECT_DIR="/Users/denispopkov/AndroidStudioProjects/SA_Neuro_Multiplatform"
SECRET_FILE="/Users/denispopkov/Desktop/secret.txt"
CACHE_UPDATED_DSP_LIB_PATH="$PROJECT_DIR/desktopApp/build/native/libdspmac.dylib"
HEROKU_PROD="/Users/denispopkov/AndroidStudioProjects/neuro-production/"
HEROKU_DEV="/Users/denispopkov/AndroidStudioProjects/neuro-test/"
HEROKU_LIBRARY="/Users/denispopkov/AndroidStudioProjects/neuro-production/files/"
HEROKU_LIBRARY_DEV="/Users/denispopkov/AndroidStudioProjects/neuro-test/files/"
ERROR_LOG_FILE="/tmp/build_error_log.txt"

post_error_message() {
  local branch_name=$1
  local message=":x: Failed to update libraries on \`$branch_name\`"
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
  HEROKU_PATH="$HEROKU_DEV"
  HEROKU_LIBRARY_PATH="$HEROKU_LIBRARY_DEV"
  ENV="dev"
else
  HEROKU_PATH="$HEROKU_PROD"
  HEROKU_LIBRARY_PATH="$HEROKU_LIBRARY"
  ENV="prod"
fi

cd "$PROJECT_DIR" || { echo "Project directory not found!"; exit 1; }

echo "Checking out branch: $BRANCH_NAME"
git stash push -m "Pre-build stash"
git fetch && git checkout "$BRANCH_NAME" && git pull origin "$BRANCH_NAME" --no-rebase

message=":hammer_and_wrench: Start X86 MacOS DSP update on \`$BRANCH_NAME\` for $ENV"
first_ts=$(post_message "${SLACK_BOT_TOKEN}" "${SLACK_CHANNEL}" "$message")

echo "Opening Android Studio..."
open -a "Android Studio"

if ! ./gradlew compileKotlin --stacktrace --info; then
  echo "Error: Gradle build failed"
  post_error_message "$BRANCH_NAME"
  exit 1
fi

sleep 10

git add .
git commit -m "add: update DSP"
git push origin "$BRANCH_NAME"

cd "$HEROKU_PATH" || { echo "Heroku project directory not found!"; exit 1; }

sleep 5

git stash push -m "Pre-build stash"
git fetch heroku && git pull heroku "master" --no-rebase

rm -rf "$HEROKU_LIBRARY_PATH/x86/libdspmac.dylib"

if [ -f "$CACHE_UPDATED_DSP_LIB_PATH" ]; then
  cp "$CACHE_UPDATED_DSP_LIB_PATH" "$HEROKU_LIBRARY_PATH/x86/"
else
  echo "Error: DSP library not found at $CACHE_UPDATED_DSP_LIB_PATH"
  post_error_message "$BRANCH_NAME"
  exit 1
fi

git add .

if ! git diff --cached --quiet; then
  git commit -m "add: update DSP lib"
  git push heroku "master"
else
  echo "[INFO] No changes to commit"
fi

message=":white_check_mark: X86 MacOS DSP library successfully updated on \`$BRANCH_NAME\` for $ENV"
execute_file_upload "${SLACK_BOT_TOKEN}" "${SLACK_CHANNEL}" "$message" "upload" "${CACHE_UPDATED_DSP_LIB_PATH}"
delete_message "${SLACK_BOT_TOKEN}" "${SLACK_CHANNEL}" "$first_ts"