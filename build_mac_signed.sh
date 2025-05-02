#!/bin/bash

source "/Users/denispopkov/PycharmProjects/AutomateBuildBackend/slack_upload.sh"
source "/Users/denispopkov/PycharmProjects/AutomateBuildBackend/utils.sh"

SECRET_FILE="/Users/denispopkov/Desktop/secret.txt"
PROJECT_DIR="/Users/denispopkov/AndroidStudioProjects/SA_Neuro_Multiplatform"
BUILD_PATH="$PROJECT_DIR/desktopApp/build"
RESOURCE_DIR="$PROJECT_DIR/desktopApp/resources"
RESOURCE_BACKUP="$PROJECT_DIR/desktopApp/resources_backup"

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

echo "Opening Android Studio..."
open -a "Android Studio"

cd "$PROJECT_DIR" || { echo "Project directory not found!"; exit 1; }

end_time=$(TZ=Asia/Omsk date -v+30M "+%H:%M")
message=":hammer_and_wrench: ARM MacOS build started. It will be ready approximately at $end_time"
first_ts=$(post_message "${SLACK_BOT_TOKEN}" "${SLACK_CHANNEL}" "$message")

VERSION_CODE=$(grep '^desktop\.build\.number\s*=' "$PROJECT_DIR/gradle.properties" | sed 's/.*=\s*\([0-9]*\)/\1/' | xargs)
VERSION_CODE=$((VERSION_CODE + 1))

# Backup and remove resources
if [ -d "$RESOURCE_DIR" ]; then
  echo "Backing up and removing resources directory..."
  rm -rf "$RESOURCE_BACKUP"
  cp -R "$RESOURCE_DIR" "$RESOURCE_BACKUP"
  rm -rf "$RESOURCE_DIR"
else
  echo "No resources directory found to back up."
fi

# Build the app
echo "Building signed build..."
./gradlew packageDmg

# Create ZIP
BUILD_PATH="$PROJECT_DIR/desktopApp/build/compose/binaries/main/app/Neuro Desktop.app"
ZIP_PATH="$PROJECT_DIR/desktopApp/build/compose/binaries/main/app/Neuro.zip"
echo "Creating ZIP file: $ZIP_PATH"
cd "$(dirname "$BUILD_PATH")" || exit 1
zip -r "$(basename "$ZIP_PATH")" "$(basename "$BUILD_PATH")"

if [ $? -eq 0 ]; then
  echo "ZIP file created successfully: $ZIP_PATH"
else
  post_error_message "$BRANCH_NAME"
  echo "Error creating ZIP file."
  # Restore resources before exit
  rm -rf "$RESOURCE_DIR"
  mv "$RESOURCE_BACKUP" "$RESOURCE_DIR"
  exit 1
fi

# Submit for notarization
echo "Submitting build for notarization..."
xcrun notarytool submit "$ZIP_PATH" \
  --apple-id "$APPLE_ID" \
  --team-id "$TEAM_ID" \
  --password "$NOTARY_PASSWORD" \
  --wait

# Restore resources directory
echo "Restoring resources directory..."
rm -rf "$RESOURCE_DIR"
mv "$RESOURCE_BACKUP" "$RESOURCE_DIR"

sleep 20
open "$BUILD_TOOL"
sleep 5

PROCESS_NAME="Packages"
trigger_build() {
  osascript <<EOF
  tell application "System Events"
    if exists application process "$PROCESS_NAME" then
      set frontmost of application process "$PROCESS_NAME" to true
      keystroke "b" using {command down}
    end if
  end tell
EOF
}

trigger_build

NOTARIZED_BUILD_PATH="/Users/denispopkov/AndroidStudioProjects/SA_Neuro_release/build/Neuro_desktop.pkg"
elapsed_time=0
TIMEOUT=60
INTERVAL=10

while [ ! -f "$NOTARIZED_BUILD_PATH" ]; do
  sleep $INTERVAL
  elapsed_time=$((elapsed_time + INTERVAL))
  if [ $elapsed_time -ge $TIMEOUT ]; then
    trigger_build
    elapsed_time=0
  fi
done

sleep 20

SIGNED_PKG_PATH="/Users/denispopkov/AndroidStudioProjects/SA_Neuro_release/build/Neuro_desktopS.pkg"
echo "$USER_PASSWORD" | sudo -S productsign --sign "Developer ID Installer: Source Audio LLC (Z2JAQC4DXV)" "$NOTARIZED_BUILD_PATH" "$SIGNED_PKG_PATH"
sleep 20

xcrun notarytool submit "$SIGNED_PKG_PATH" \
  --apple-id "$APPLE_ID" \
  --team-id "$TEAM_ID" \
  --password "$NOTARY_PASSWORD" \
  --wait

BUILD_DIR="/Users/denispopkov/AndroidStudioProjects/SA_Neuro_release/build"
BASE_NAME="neuro_desktop_${VERSION_NAME}-[${VERSION_CODE}]_installer_mac.pkg"
NEW_PKG_PATH="$BUILD_DIR/$BASE_NAME"

INDEX=1
while [ -f "$NEW_PKG_PATH" ]; do
  NEW_PKG_PATH="$BUILD_DIR/neuro_desktop_${VERSION_NAME}-[${VERSION_CODE}]_installer_mac_${INDEX}.pkg"
  INDEX=$((INDEX + 1))
done

mv "$SIGNED_PKG_PATH" "$NEW_PKG_PATH" || exit 1

SIGNATURE_CHECK=$(pkgutil --check-signature "$NEW_PKG_PATH")
if [[ "$SIGNATURE_CHECK" != *"Developer ID Installer: Source Audio LLC"* ]]; then exit 1; fi

execute_file_upload "${SLACK_BOT_TOKEN}" "${SLACK_CHANNEL}" ":white_check_mark: ARM MacOS" "upload" "${NEW_PKG_PATH}"
if [ $? -ne 0 ]; then exit 1; fi

DESKTOP_BUILD_PATH="$PROJECT_DIR/desktopApp/build/compose/binaries/main"
if [ -d "$DESKTOP_BUILD_PATH" ]; then rm -r "$DESKTOP_BUILD_PATH"; fi

pkill -f "$PROCESS_NAME"

if [ -f "$NOTARIZED_BUILD_PATH" ]; then rm "$NOTARIZED_BUILD_PATH"; fi

delete_message "${SLACK_BOT_TOKEN}" "${SLACK_CHANNEL}" "$first_ts"
