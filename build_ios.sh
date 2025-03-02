#!/bin/bash

source "/Users/denispopkov/PycharmProjects/AutomateBuildBackend/slack_upload.sh"

IOS_APP_PATH="/Users/denispopkov/AndroidStudioProjects/SA_Neuro_Multiplatform/iosApp"
PBXPROJ_PATH="$IOS_APP_PATH/iosApp.xcodeproj/project.pbxproj"
INFO_PLIST_PATH="$IOS_APP_PATH/iosApp/app/Info.plist"
FASTFILE_PATH="/Users/denispopkov/AndroidStudioProjects/SA_Neuro_Multiplatform/iosApp/fastlane/Fastfile"
CACHE_PATH="/Users/denispopkov/AndroidStudioProjects/SA_Neuro_Multiplatform/shared/build"
FILE_TO_DELETE="/Users/denispopkov/AndroidStudioProjects/SA_Neuro_Multiplatform/shared/src/commonMain/resources/MR/files/libdspmac.dylib"
FILE_BACKUP_PATH="/Users/denispopkov/Desktop/libdspmac.dylib"
SWIFT_FILE_SOURCE="/Users/denispopkov/Desktop/SA_Neuro_Multiplatform_shared.swift"
SWIFT_TARGET_DIR="/Users/denispopkov/AndroidStudioProjects/SA_Neuro_Multiplatform/shared/build/bin/iosArm64/podDebugFramework/sharedSwift"
SWIFT_TARGET_FILE="$SWIFT_TARGET_DIR/SA_Neuro_Multiplatform_shared.swift"
SECRET_FILE="/Users/denispopkov/Desktop/secret.txt"

PROJECT_DIR="/Users/denispopkov/AndroidStudioProjects/SA_Neuro_Multiplatform"
cd "$PROJECT_DIR" || { echo "Project directory not found!"; exit 1; }

# For dev analytics
SHARED_GRADLE_FILE="$PROJECT_DIR/shared/build.gradle.kts"
PROD_SHARED_GRADLE_FILE="/Users/denispopkov/Desktop/prod/build.gradle.kts"

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
  esac
done < "$SECRET_FILE"

BRANCH_NAME=$1
isUseDevAnalytics=$2

# Checkout branch
if [ -z "$BRANCH_NAME" ]; then
  echo "Error: Branch name is required"
  exit 1
fi

git fetch && git checkout "$BRANCH_NAME" && git pull origin "$BRANCH_NAME" --no-rebase

cd "$IOS_APP_PATH" || exit

LAST_BUILD_NUMBER=$(agvtool what-version -terse)
NEW_VERSION=$((LAST_BUILD_NUMBER + 1))

end_time=$(TZ=Asia/Omsk date -v+15M "+%H:%M")
message="iOS build started. It will be ready approximately at $end_time Omsk Time."
execute_file_upload "${SLACK_BOT_TOKEN}" "${SLACK_CHANNEL}" "$message" "message"

# Update project.pbxproj
if [ -f "$PBXPROJ_PATH" ]; then
  sed -i '' "s/CURRENT_PROJECT_VERSION = $LAST_BUILD_NUMBER;/CURRENT_PROJECT_VERSION = $NEW_VERSION;/" "$PBXPROJ_PATH"

  MARKETING_VERSION=$(grep -o 'MARKETING_VERSION = [^;]*' "$PBXPROJ_PATH" | sed -E 's/.*= (.*)/\1/' | head -n 1)
  MARKETING_VERSION=$(echo "$MARKETING_VERSION" | xargs)
  VERSION_NUMBER="$MARKETING_VERSION"
else
  echo "project.pbxproj not found: $PBXPROJ_PATH"
  exit 1
fi

# Update Info.plist
if [ -f "$INFO_PLIST_PATH" ]; then
  /usr/libexec/PlistBuddy -c "Set :CFBundleVersion $NEW_VERSION" "$INFO_PLIST_PATH"
else
  echo "Info.plist not found: $INFO_PLIST_PATH"
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

# Move file to backup location
if [ -f "$FILE_TO_DELETE" ]; then
  mv "$FILE_TO_DELETE" "$FILE_BACKUP_PATH"
  echo "Moved file from $FILE_TO_DELETE to $FILE_BACKUP_PATH"
else
  echo "File not found at $FILE_TO_DELETE, skipping move"
fi

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

# Run Fastlane with fallback
if fastlane testflight_upload; then
  git pull origin "$BRANCH_NAME" --no-rebase
  git stash push -m "Stashing build.gradle.kts" --keep-index -- "$PROJECT_DIR/shared/build.gradle.kts"
  git add .
  git commit -m "iOS version bump to $NEW_VERSION"
  git push

  execute_file_upload "${SLACK_BOT_TOKEN}" "${SLACK_CHANNEL}" "New iOS build uploaded to TestFlight with v$VERSION_NUMBER ($NEW_VERSION) from $BRANCH_NAME" "message"
else
  execute_file_upload "${SLACK_BOT_TOKEN}" "${SLACK_CHANNEL}" "iOS build failed :crycat:" "message"
  echo "Fastlane failed. Not committing changes or sending Slack message."
fi

# Restore the file after Fastlane execution
if [ -f "$FILE_BACKUP_PATH" ]; then
  mv "$FILE_BACKUP_PATH" "$FILE_TO_DELETE"
  echo "Restored file from $FILE_BACKUP_PATH to $FILE_TO_DELETE"

  # Delete the backup file after restoration
  if [ -f "$FILE_BACKUP_PATH" ]; then
    rm "$FILE_BACKUP_PATH"
    echo "Deleted backup file: $FILE_BACKUP_PATH"
  fi
else
  echo "Backup file not found at $FILE_BACKUP_PATH, skipping restore"
fi
