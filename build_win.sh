#!/bin/bash

source "C:\Users\BlackBricks\PycharmProjects\AutomateBuildBackend\slack_upload.sh"

SECRET_FILE="C:\Users\BlackBricks\Desktop\secret.txt"

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
BUMP_VERSION=$2

if [ -z "$BRANCH_NAME" ]; then
  echo "Error: Branch name is required"
  exit 1
fi

PROJECT_DIR="C:\Users\BlackBricks\StudioProjects\SA_Neuro_Multiplatform"
cd "$PROJECT_DIR" || { echo "Project directory not found!"; exit 1; }

echo "Checking out branch: $BRANCH_NAME"
git fetch && git checkout "$BRANCH_NAME" && git pull origin "$BRANCH_NAME"

VERSION_CODE=$(grep '^desktop\.build\.number\s*=' "$PROJECT_DIR\gradle.properties" | sed 's/.*=\s*\([0-9]*\)/\1/' | xargs)
VERSION_NAME=$(grep '^desktop\.version\s*=' "$PROJECT_DIR\gradle.properties" | sed 's/.*=\s*\([0-9]*\.[0-9]*\.[0-9]*\)/\1/' | xargs)

if [ -z "$VERSION_CODE" ] || [ -z "$VERSION_NAME" ]; then
  echo "Error: Unable to extract versionCode or versionName from gradle.properties"
  exit 1
fi

if [ "$BUMP_VERSION" == "true" ]; then
  VERSION_CODE=$((VERSION_CODE + 1))
  sed -i "" "s/^desktop\.build\.number\s*=\s*[0-9]*$/desktop.build.number=$VERSION_CODE/" "$PROJECT_DIR\gradle.properties"
else
  echo "Nothing to bump"
fi

BUILD_PATH="$PROJECT_DIR\desktopApp\build"
DESKTOP_BUILD_PATH="$PROJECT_DIR\desktopApp\build\compose\binaries\main-release\msi"
FINAL_MSI_PATH="$DESKTOP_BUILD_PATH\Neuro Desktop-3.0.25.msi"

rm -rf "$BUILD_PATH"

echo "Building..."
./gradlew packageReleaseMsi

if [ "$BUMP_VERSION" == "true" ]; then
    VERSION_CODE=$((VERSION_CODE + 1))
else
   echo "Bump is false"
fi

echo "Uploading renamed .msi to Slack..."
execute_file_upload "${SLACK_BOT_TOKEN}" "${SLACK_CHANNEL}" "Windows MSI signed from $BRANCH_NAME" "upload" "${FINAL_MSI_PATH}"

if [ $? -eq 0 ]; then
    echo "MSI sent to Slack successfully."
    git add .
    git commit -m "Update hardcoded libs"
    git push origin "$BRANCH_NAME"
else
    echo "Error committing hardcoded lib."
    exit 1
fi

if [ -d "$DESKTOP_BUILD_PATH" ]; then
    rm -r "$DESKTOP_BUILD_PATH"
    echo "Removed directory: $DESKTOP_BUILD_PATH"
else
    echo "Directory does not exist: $DESKTOP_BUILD_PATH"
fi

if [ "$BUMP_VERSION" == "true" ]; then
    git fetch && git pull origin "$BRANCH_NAME"
    git add .
    git commit -m "win version bump to $VERSION_CODE"
    git push origin "$BRANCH_NAME"

    echo "Version bump completed successfully. New versionCode: $VERSION_CODE"
else
    echo "Skipping version bump as bumpVersion is false."
fi
