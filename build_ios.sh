#!/bin/bash

source "/Users/denispopkov/PycharmProjects/AutomateBuildBackend/slack_upload.sh"

# Set path variables
IOS_APP_PATH="/Users/denispopkov/AndroidStudioProjects/SA_Neuro_Multiplatform/iosApp"
PBXPROJ_PATH="$IOS_APP_PATH/iosApp.xcodeproj/project.pbxproj"
INFO_PLIST_PATH="$IOS_APP_PATH/iosApp/app/Info.plist"
FASTFILE_PATH="/Users/denispopkov/AndroidStudioProjects/SA_Neuro_Multiplatform/iosApp/fastlane/Fastfile"
CACHE_PATH="/Users/denispopkov/AndroidStudioProjects/SA_Neuro_Multiplatform/shared/build"
FILE_TO_DELETE="/Users/denispopkov/AndroidStudioProjects/SA_Neuro_Multiplatform/shared/src/commonMain/resources/MR/files/libdspmac.dylib"
FILE_BACKUP_PATH="/Users/denispopkov/Desktop/SIGN/libdspmac.dylib"
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
    "KEYFILE") KEYFILE="$value" ;;
    "KEY_ALIAS") KEY_ALIAS="$value" ;;
    "KEY_PASSWORD") KEY_PASSWORD="$value" ;;
  esac
done < "$SECRET_FILE"

# Extract the current version from project.pbxproj
if [ -f "$PBXPROJ_PATH" ]; then
  CURRENT_VERSION=$(grep -o 'CURRENT_PROJECT_VERSION = [0-9]\+;' "$PBXPROJ_PATH" | sed -E 's/.*= ([0-9]+);/\1/' | head -n 1)
  CURRENT_VERSION=$(echo "$CURRENT_VERSION" | xargs)
  echo "Extracted CURRENT_PROJECT_VERSION: '$CURRENT_VERSION'"

  # Ensure CURRENT_VERSION is valid and increment
  if [[ "$CURRENT_VERSION" =~ ^[0-9]+$ ]]; then
    NEW_VERSION=$((CURRENT_VERSION + 1))
    sed -i '' "s/CURRENT_PROJECT_VERSION = $CURRENT_VERSION;/CURRENT_PROJECT_VERSION = $NEW_VERSION;/" "$PBXPROJ_PATH"
    echo "Updated project version from $CURRENT_VERSION to $NEW_VERSION in project.pbxproj"
  else
    echo "Error: Unable to extract a valid CURRENT_PROJECT_VERSION from project.pbxproj"
    exit 1
  fi

  # Extract the MARKETING_VERSION and set VERSION_NUMBER
  MARKETING_VERSION=$(grep -o 'MARKETING_VERSION = [^;]*' "$PBXPROJ_PATH" | sed -E 's/.*= (.*)/\1/' | head -n 1)
  MARKETING_VERSION=$(echo "$MARKETING_VERSION" | xargs)
  echo "Extracted MARKETING_VERSION: '$MARKETING_VERSION'"

  if [ -z "$MARKETING_VERSION" ]; then
    echo "Error: Unable to extract MARKETING_VERSION from project.pbxproj"
    exit 1
  fi
  VERSION_NUMBER="$MARKETING_VERSION"
else
  echo "project.pbxproj not found: $PBXPROJ_PATH"
  exit 1
fi

# Extract and bump version in Info.plist
if [ -f "$INFO_PLIST_PATH" ]; then
  CURRENT_CF_BUNDLE_VERSION=$(grep -A 1 "<key>CFBundleVersion</key>" "$INFO_PLIST_PATH" | tail -n 1 | sed 's/^[[:space:]]*<string>\([0-9]*\)<\/string>/\1/')
  PLACEHOLDER_CF_BUNDLE_VERSION=$(grep -A 1 "<key>CFBundleVersion</key>" "$INFO_PLIST_PATH" | tail -n 1 | sed 's/^[[:space:]]*<string>\(.*\)<\/string>/\1/')
  echo "Extracted CFBundleVersion: '$CURRENT_CF_BUNDLE_VERSION'"
  echo "Extracted CFBundleVersion Placeholder: '$PLACEHOLDER_CF_BUNDLE_VERSION'"

  if [[ "$PLACEHOLDER_CF_BUNDLE_VERSION" == "\$(CURRENT_PROJECT_VERSION)" ]]; then
    /usr/libexec/PlistBuddy -c "Set :CFBundleVersion $NEW_VERSION" "$INFO_PLIST_PATH"
    echo "Replaced CFBundleVersion placeholder with $NEW_VERSION in Info.plist"
  elif [[ "$CURRENT_CF_BUNDLE_VERSION" =~ ^[0-9]+$ ]]; then
    /usr/libexec/PlistBuddy -c "Set :CFBundleVersion $NEW_VERSION" "$INFO_PLIST_PATH"
    echo "Updated CFBundleVersion to $NEW_VERSION in Info.plist"
  else
    echo "Error: Unable to extract a valid CFBundleVersion from Info.plist"
    exit 1
  fi
else
  echo "Info.plist not found: $INFO_PLIST_PATH"
  exit 1
fi

# Fetch and checkout the requested branch
BRANCH_NAME=$1

if [ -z "$BRANCH_NAME" ]; then
  echo "Error: Branch name is required"
  exit 1
fi

open -a "Android Studio"

PROJECT_DIR="/Users/denispopkov/AndroidStudioProjects/SA_Neuro_Multiplatform"
cd "$PROJECT_DIR" || { echo "Project directory not found!"; exit 1; }

echo "Checking out branch: $BRANCH_NAME"
git fetch && git checkout "$BRANCH_NAME" && git pull origin "$BRANCH_NAME"

# Update Fastfile with the new branch name
if [ -f "$FASTFILE_PATH" ]; then
  sed -i '' "s/ensure_git_branch(branch: 'sc_fastlane')/ensure_git_branch(branch: '$BRANCH_NAME')/" "$FASTFILE_PATH"
  echo "Updated Fastfile with branch: $BRANCH_NAME"
else
  echo "Fastfile not found: $FASTFILE_PATH"
  exit 1
fi

# Delete dsp lib
if [ -f "$FILE_TO_DELETE" ]; then
  rm "$FILE_TO_DELETE"
  echo "Deleted file: $FILE_TO_DELETE"
else
  echo "File not found: $FILE_TO_DELETE"
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

# Copy Swift file to target directory
if [ -f "$SWIFT_FILE_SOURCE" ]; then
  cp "$SWIFT_FILE_SOURCE" "$SWIFT_TARGET_FILE"
  echo "Copied Swift file to: $SWIFT_TARGET_FILE"
else
  echo "Swift source file not found: $SWIFT_FILE_SOURCE"
  exit 1
fi

cd "$IOS_APP_PATH" || exit

# Run Fastlane
fastlane testflight_upload

echo "Checking out branch: $BRANCH_NAME"
git fetch && git pull origin "$BRANCH_NAME"

# Restore dsp lib
if [ -f "$FILE_BACKUP_PATH" ]; then
  cp "$FILE_BACKUP_PATH" "$FILE_TO_DELETE"
  echo "Restored file: $FILE_TO_DELETE from $FILE_BACKUP_PATH"
else
  echo "Backup file not found: $FILE_BACKUP_PATH"
  exit 1
fi

# Commit and push the changes
git add .
git commit -m "add: iOS version bump to $NEW_VERSION"
git push

execute_file_upload "${SLACK_BOT_TOKEN}" "${SLACK_CHANNEL}" "New iOS build uploaded to TestFlight\n\nv$VERSION_NUMBER ($NEW_VERSION) from $BRANCH_NAME" "message"
