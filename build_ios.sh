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

# Checkout branch
BRANCH_NAME=$1
if [ -z "$BRANCH_NAME" ]; then
  echo "Error: Branch name is required"
  exit 1
fi

# Extract the current version from project.pbxproj
if [ -f "$PBXPROJ_PATH" ]; then
  CURRENT_VERSION=$(grep -o 'CURRENT_PROJECT_VERSION = [0-9]\+;' "$PBXPROJ_PATH" | sed -E 's/.*= ([0-9]+);/\1/' | head -n 1)
  CURRENT_VERSION=$(echo "$CURRENT_VERSION" | xargs)

  if [[ "$CURRENT_VERSION" =~ ^[0-9]+$ ]]; then
    NEW_VERSION=$((CURRENT_VERSION + 1))
    sed -i '' "s/CURRENT_PROJECT_VERSION = $CURRENT_VERSION;/CURRENT_PROJECT_VERSION = $NEW_VERSION;/" "$PBXPROJ_PATH"
  else
    echo "Error: Unable to extract a valid CURRENT_PROJECT_VERSION from project.pbxproj"
    exit 1
  fi

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

git fetch && git checkout "$BRANCH_NAME" && git pull origin "$BRANCH_NAME"

# Update Fastfile
if [ -f "$FASTFILE_PATH" ]; then
  sed -i '' "s/ensure_git_branch(branch: 'sc_fastlane')/ensure_git_branch(branch: '$BRANCH_NAME')/" "$FASTFILE_PATH"
else
  echo "Fastfile not found: $FASTFILE_PATH"
  exit 1
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
  git fetch && git pull origin "$BRANCH_NAME"
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
