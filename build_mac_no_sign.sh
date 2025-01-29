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

BRANCH_NAME=$1

if [ -z "$BRANCH_NAME" ]; then
  echo "Error: Branch name is required"
  exit 1
fi

echo "Opening Android Studio..."
open -a "Android Studio"

PROJECT_DIR="/Users/denispopkov/AndroidStudioProjects/SA_Neuro_Multiplatform"
cd "$PROJECT_DIR" || { echo "Project directory not found!"; exit 1; }

echo "Checking out branch: $BRANCH_NAME"
git fetch && git checkout "$BRANCH_NAME" && git pull origin "$BRANCH_NAME"

VERSION_CODE=$(grep '^desktop\.build\.number\s*=' "$PROJECT_DIR/gradle.properties" | sed 's/.*=\s*\([0-9]*\)/\1/' | xargs)
VERSION_NAME=$(grep '^desktop\.version\s*=' "$PROJECT_DIR/gradle.properties" | sed 's/.*=\s*\([0-9]*\.[0-9]*\.[0-9]*\)/\1/' | xargs)

if [ -z "$VERSION_CODE" ] || [ -z "$VERSION_NAME" ]; then
  echo "Error: Unable to extract versionCode or versionName from gradle.properties"
  exit 1
fi

# Building
echo "Building no-signed build..."
./gradlew packageDmg

# Find the build
BUILD_PATH="$PROJECT_DIR/desktopApp/build/compose/binaries/main/dmg/Neuro Desktop-$VERSION_CODE.dmg"

if [ ! -f "$BUILD_PATH" ]; then
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
