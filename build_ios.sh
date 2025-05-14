#!/bin/bash

source "/Users/denispopkov/PycharmProjects/AutomateBuildBackend/slack_upload.sh"
source "/Users/denispopkov/PycharmProjects/AutomateBuildBackend/utils.sh"

IOS_APP_PATH="/Users/denispopkov/AndroidStudioProjects/SA_Neuro_Multiplatform/iosApp"
PBXPROJ_PATH="$IOS_APP_PATH/iosApp.xcodeproj/project.pbxproj"
INFO_PLIST_PATH="$IOS_APP_PATH/iosApp/app/Info.plist"
FASTFILE_PATH="/Users/denispopkov/AndroidStudioProjects/SA_Neuro_Multiplatform/iosApp/fastlane/Fastfile"
CACHE_PATH="/Users/denispopkov/AndroidStudioProjects/SA_Neuro_Multiplatform/shared/build"
DYLIB_PATH="/Users/denispopkov/AndroidStudioProjects/SA_Neuro_Multiplatform/shared/src/commonMain/resources/MR/files/libkeychainbridge.dylib"
DYLIB_FILE_BACKUP_PATH="/Users/denispopkov/Desktop/libkeychainbridge.dylib"
SWIFT_FILE_SOURCE="/Users/denispopkov/Desktop/SA_Neuro_Multiplatform_shared.swift"
SWIFT_TARGET_DIR="/Users/denispopkov/AndroidStudioProjects/SA_Neuro_Multiplatform/shared/build/bin/iosArm64/podDebugFramework/sharedSwift"
SWIFT_TARGET_FILE="$SWIFT_TARGET_DIR/SA_Neuro_Multiplatform_shared.swift"
SECRET_FILE="/Users/denispopkov/Desktop/secret.txt"
ERROR_LOG_FILE="/tmp/build_error_log.txt"

PROJECT_DIR="/Users/denispopkov/AndroidStudioProjects/SA_Neuro_Multiplatform"
cd "$PROJECT_DIR" || { echo "Project directory not found!"; exit 1; }

while IFS='=' read -r key value; do
  key=$(echo "$key" | xargs)
  value=$(echo "$value" | xargs)

  case "$key" in
    "SLACK_BOT_TOKEN") SLACK_BOT_TOKEN="$value" ;;
    "SLACK_CHANNEL") SLACK_CHANNEL="$value" ;;
  esac
done < "$SECRET_FILE"

BRANCH_NAME=$1
isUseDevAnalytics=$2

post_error_message() {
  local branch_name=$1
  local message=":x: Failed to build iOS on \`$branch_name\`"
  execute_file_upload "${SLACK_BOT_TOKEN}" "${SLACK_CHANNEL}" "$message" "upload" "$ERROR_LOG_FILE"
}

analyticsMessage=""

if [ "$isUseDevAnalytics" == "true" ]; then
  analyticsMessage="dev"
else
  analyticsMessage="prod"
fi

git fetch && git checkout "$BRANCH_NAME" && git pull origin "$BRANCH_NAME" --no-rebase

cd "$IOS_APP_PATH" || exit

LAST_BUILD_NUMBER=$(agvtool what-version -terse)
NEW_VERSION=$((LAST_BUILD_NUMBER + 1))

end_time=$(TZ=Asia/Omsk date -v+15M "+%H:%M")
message=":hammer_and_wrench: iOS build started on \`$BRANCH_NAME\` with $analyticsMessage analytics. It will be ready approximately at $end_time"
first_ts=$(post_message "${SLACK_BOT_TOKEN}" "${SLACK_CHANNEL}" "$message")

# Update project.pbxproj
if [ -f "$PBXPROJ_PATH" ]; then
  sed -i '' "s/CURRENT_PROJECT_VERSION = $LAST_BUILD_NUMBER;/CURRENT_PROJECT_VERSION = $NEW_VERSION;/" "$PBXPROJ_PATH"

  MARKETING_VERSION=$(grep -o 'MARKETING_VERSION = [^;]*' "$PBXPROJ_PATH" | sed -E 's/.*= (.*)/\1/' | head -n 1)
  MARKETING_VERSION=$(echo "$MARKETING_VERSION" | xargs)
  VERSION_NUMBER="$MARKETING_VERSION"
else
  echo "project.pbxproj not found: $PBXPROJ_PATH"
  post_error_message "$BRANCH_NAME"
  exit 1
fi

# Update Info.plist
if [ -f "$INFO_PLIST_PATH" ]; then
  /usr/libexec/PlistBuddy -c "Set :CFBundleVersion $NEW_VERSION" "$INFO_PLIST_PATH"
else
  echo "Info.plist not found: $INFO_PLIST_PATH"
  post_error_message "$BRANCH_NAME"
  exit 1
fi

ESCAPED_BRANCH_NAME=$(printf '%s\n' "$BRANCH_NAME" | sed -e 's/[\/&]/\\&/g')

# Detect OS and set sed flag accordingly
if [[ "$OSTYPE" == "darwin"* ]]; then
  sed -i "" "s/branch: '[^']*'/branch: '$ESCAPED_BRANCH_NAME'/" "$FASTFILE_PATH"
else
  sed -i "s/branch: '[^']*'/branch: '$ESCAPED_BRANCH_NAME'/" "$FASTFILE_PATH"
fi

if [ "$isUseDevAnalytics" == "false" ]; then
  enable_prod_keys
  echo "applied prod analytics"

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

# Move files to backup locations
move_file() {
  local file_path=$1
  local backup_path=$2
  if [ -f "$file_path" ]; then
    mv "$file_path" "$backup_path"
    echo "Moved file from $file_path to $backup_path"
  else
    echo "File not found at $file_path, skipping move"
  fi
}

move_file "$DYLIB_PATH" "$DYLIB_FILE_BACKUP_PATH"

# Delete cache directory
if [ -d "$CACHE_PATH" ]; then
  rm -rf "$CACHE_PATH"
  echo "Deleted cache directory: $CACHE_PATH"
else
  echo "Cache directory not found: $CACHE_PATH"
fi

# Create Swift target directory
mkdir -p "$SWIFT_TARGET_DIR"
cp "$SWIFT_FILE_SOURCE" "$SWIFT_TARGET_FILE"

cd "$IOS_APP_PATH" || exit

undo_enable_prod_keys

sleep 5

# Run Fastlane with fallback
if fastlane testflight_upload; then
  git pull origin "$BRANCH_NAME" --no-rebase
  git add .
  git commit -m "iOS version bump to $NEW_VERSION"
  git push

  execute_file_upload "${SLACK_BOT_TOKEN}" "${SLACK_CHANNEL}" ":white_check_mark: iOS build uploaded to TestFlight with v$VERSION_NUMBER ($NEW_VERSION) with ${analyticsMessage} analytics" "message"
else
  post_error_message "$BRANCH_NAME"
  echo "Fastlane failed. Not committing changes or sending Slack message."
fi

restore_file() {
  local backup_path=$1
  local file_path=$2
  if [ -f "$backup_path" ]; then
    mv "$backup_path" "$file_path"
    echo "Restored file from $backup_path to $file_path"

    rm "$backup_path"
    echo "Deleted backup file: $backup_path"
  else
    echo "Backup file not found at $backup_path, skipping restore"
  fi
}

restore_file "$DYLIB_FILE_BACKUP_PATH" "$DYLIB_PATH"

delete_message "${SLACK_BOT_TOKEN}" "${SLACK_CHANNEL}" "$first_ts"
