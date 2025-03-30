#!/bin/bash

source "/Users/denispopkov/PycharmProjects/AutomateBuildBackend/slack_upload.sh"
source "/Users/denispopkov/PycharmProjects/AutomateBuildBackend/utils.sh"

SECRET_FILE="/Users/denispopkov/Desktop/secret.txt"

while IFS='=' read -r key value; do
  key=$(echo "$key" | xargs)
  value=$(echo "$value" | xargs)

  case "$key" in
    "SLACK_BOT_TOKEN") SLACK_BOT_TOKEN="$value" ;;
    "SLACK_CHANNEL") SLACK_CHANNEL="$value" ;;
    "USER_PASSWORD") USER_PASSWORD="$value" ;;
  esac
done < "$SECRET_FILE"

BRANCH_NAME=$1
isUseDevAnalytics=$2

echo "Opening Android Studio..."
open -a "Android Studio"

analyticsMessage=""

if [ "$isUseDevAnalytics" == "true" ]; then
  analyticsMessage="dev"
else
  analyticsMessage="prod"
fi

end_time=$(TZ=Asia/Omsk date -v+32M "+%H:%M")
message=":hammer_and_wrench: MacOS build started on \`$BRANCH_NAME\`
:mag_right: Analytics look on $analyticsMessage
:clock2: It will be ready approximately at $end_time"
post_message "${SLACK_BOT_TOKEN}" "${SLACK_CHANNEL}" "$message"

PROJECT_DIR="/Users/denispopkov/AndroidStudioProjects/SA_Neuro_Multiplatform"
cd "$PROJECT_DIR" || { echo "Project directory not found!"; exit 1; }

echo "Checking out branch: $BRANCH_NAME"
git stash push -m "Pre-build stash"
git fetch && git checkout "$BRANCH_NAME" && git pull origin "$BRANCH_NAME" --no-rebase

VERSION_CODE=$(grep '^desktop\.build\.number\s*=' "$PROJECT_DIR/gradle.properties" | sed 's/.*=\s*\([0-9]*\)/\1/' | xargs)
VERSION_NAME=$(grep '^desktop\.version\s*=' "$PROJECT_DIR/gradle.properties" | sed 's/.*=\s*\([0-9]*\.[0-9]*\.[0-9]*\)/\1/' | xargs)

VERSION_CODE=$((VERSION_CODE + 1))
sed -i '' "s/^desktop\.build\.number\s*=\s*[0-9]*$/desktop.build.number=$VERSION_CODE/" "$PROJECT_DIR/gradle.properties"
git pull origin "$BRANCH_NAME" --no-rebase
git add .
git commit -m "macOS version bump to $VERSION_CODE"
git push origin "$BRANCH_NAME"

BUILD_PATH="$PROJECT_DIR/desktopApp/build"

if [ "$isUseDevAnalytics" == "false" ]; then
  enable_prod_keys

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

# Building
echo "Building signed build..."
./gradlew packageDmg

# Find the build
BUILD_PATH="$PROJECT_DIR/desktopApp/build/compose/binaries/main/app/Neuro Desktop.app"

if [ ! -d "$BUILD_PATH" ]; then
  echo "Error: Signed Build not found at expected path: $BUILD_PATH"
  exit 1
fi

echo "Built successfully: $BUILD_PATH"

## Signing the .pkg
SIGNED_PKG_PATH="/Users/denispopkov/AndroidStudioProjects/SA_Neuro_release/build/Neuro_desktopS.pkg"
echo "Signing the .pkg file..."
echo "$USER_PASSWORD" | sudo -S productsign --sign "Developer ID Installer: Source Audio LLC (Z2JAQC4DXV)" "$NOTARIZED_BUILD_PATH" "$SIGNED_PKG_PATH"

# Rename signed .pkg to final format in-place
BUILD_DIR="/Users/denispopkov/AndroidStudioProjects/SA_Neuro_release/build"
BASE_NAME="neuro_desktop_${VERSION_NAME}-[${VERSION_CODE}]_installer_mac.pkg"
NEW_PKG_PATH="$BUILD_DIR/$BASE_NAME"

# Check for existing files and find unique name
INDEX=1
while [ -f "$NEW_PKG_PATH" ]; do
    NEW_PKG_PATH="$BUILD_DIR/neuro_desktop_${VERSION_NAME}-[${VERSION_CODE}]_installer_mac_${INDEX}.pkg"
    INDEX=$((INDEX + 1))
done

mv "$SIGNED_PKG_PATH" "$NEW_PKG_PATH" || { echo "Error renaming .pkg"; exit 1; }
echo "Final package path: $NEW_PKG_PATH"

echo "Uploading renamed .pkg to Slack..."
execute_file_upload "${SLACK_BOT_TOKEN}" "${SLACK_CHANNEL}" "macOS signed from $BRANCH_NAME" "upload" "${NEW_PKG_PATH}"

sleep 10

undo_enable_prod_keys

sleep 5

echo "PKG sent to Slack successfully."
git pull origin "$BRANCH_NAME" --no-rebase
git add .
git commit -m "Update hardcoded libs"
git push origin "$BRANCH_NAME"

