#!/bin/bash

source "/Users/denispopkov/PycharmProjects/AutomateBuildBackend/slack_upload.sh"

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

# For dev analytics
SHARED_GRADLE_FILE="$PROJECT_DIR/shared/build.gradle.kts"
PROD_SHARED_GRADLE_FILE="/Users/denispopkov/Desktop/prod/build.gradle.kts"

BRANCH_NAME=$1
isUseDevAnalytics=$2

if [ -z "$BRANCH_NAME" ]; then
  echo "Error: Branch name is required"
  exit 1
fi

echo "Opening Android Studio..."
open -a "Android Studio"

PROJECT_DIR="/Users/denispopkov/AndroidStudioProjects/SA_Neuro_Multiplatform"
cd "$PROJECT_DIR" || { echo "Project directory not found!"; exit 1; }

echo "Checking out branch: $BRANCH_NAME"
git stash push -m "Pre-build stash"
git fetch && git checkout "$BRANCH_NAME" && git pull origin "$BRANCH_NAME" --no-rebase

end_time=$(TZ=Asia/Omsk date -v+15M "+%H:%M")
message="macOS build started. It will be ready approximately at $end_time Omsk Time."
execute_file_upload "${SLACK_BOT_TOKEN}" "${SLACK_CHANNEL}" "$message" "message"

VERSION_CODE=$(grep '^desktop\.build\.number\s*=' "$PROJECT_DIR/gradle.properties" | sed 's/.*=\s*\([0-9]*\)/\1/' | xargs)
VERSION_NAME=$(grep '^desktop\.version\s*=' "$PROJECT_DIR/gradle.properties" | sed 's/.*=\s*\([0-9]*\.[0-9]*\.[0-9]*\)/\1/' | xargs)

if [ -z "$VERSION_CODE" ] || [ -z "$VERSION_NAME" ]; then
  echo "Error: Unable to extract versionCode or versionName from gradle.properties"
  exit 1
fi

if [ "$isUseDevAnalytics" == "false" ]; then
  echo "Replacing $SHARED_GRADLE_FILE with $PROD_SHARED_GRADLE_FILE"
  rm -f "$SHARED_GRADLE_FILE"
  cp "$PROD_SHARED_GRADLE_FILE" "$SHARED_GRADLE_FILE"
  else
    echo "Nothing to change with analytics"
fi

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

# Building
echo "Building no-signed build..."
./gradlew packageDmg

# Find the build
BUILD_PATH="$PROJECT_DIR/desktopApp/build/compose/binaries/main/dmg/Neuro Desktop-$VERSION_NAME.dmg"

if [ ! -f "$BUILD_PATH" ]; then
  execute_file_upload "${SLACK_BOT_TOKEN}" "${SLACK_CHANNEL}" "macOS build failed :crycat:" "message"
  echo "Error: Signed Build not found at expected path: $BUILD_PATH"
  exit 1
fi

echo "Built successfully: $BUILD_PATH"

# Rename the file to replace spaces with underscores
NEW_BUILD_PATH="${BUILD_PATH// /_}"

# Rename the actual file on disk
mv "$BUILD_PATH" "$NEW_BUILD_PATH"

echo "Renamed file: '$NEW_BUILD_PATH'"

# Upload Build to Slack
echo "Uploading build to Slack..."
execute_file_upload "${SLACK_BOT_TOKEN}" "${SLACK_CHANNEL}" "macOS not signed from $BRANCH_NAME" "upload" "${NEW_BUILD_PATH}"

if [ $? -eq 0 ]; then
    echo "Build sent to Slack successfully."
else
    echo "Error sending Build to Slack."
    exit 1
fi

## Releasing after build
DESKTOP_BUILD_PATH="$PROJECT_DIR/desktopApp/build/compose/binaries/main"

if [ -d "$DESKTOP_BUILD_PATH" ]; then
    rm -r "$DESKTOP_BUILD_PATH"
    echo "Removed directory: $DESKTOP_BUILD_PATH"
else
    echo "Directory does not exist: $DESKTOP_BUILD_PATH"
fi
