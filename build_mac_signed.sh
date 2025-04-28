#!/bin/bash

source "/Users/denispopkov/PycharmProjects/AutomateBuildBackend/slack_upload.sh"
source "/Users/denispopkov/PycharmProjects/AutomateBuildBackend/utils.sh"

PROJECT_DIR="/Users/denispopkov/AndroidStudioProjects/SA_Neuro_Multiplatform"
SECRET_FILE="/Users/denispopkov/Desktop/secret.txt"
BUILD_TOOL="/Users/denispopkov/AndroidStudioProjects/SA_Neuro_release/Neuro_desktop.pkgproj"
DYLIB_PATH="$PROJECT_DIR/shared/src/commonMain/resources/MR/files/libkeychainbridge.dylib"
BUILD_PATH="$PROJECT_DIR/desktopApp/build"
DYLIB_RELATIVE_PATH="shared/src/commonMain/resources/MR/files/libkeychainbridge.dylib"
ERROR_LOG_FILE="/tmp/build_error_log.txt"

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

post_error_message() {
  local branch_name=$1
  local message=":x: Failed to build MacOS on \`$branch_name\`"
  execute_file_upload "${SLACK_BOT_TOKEN}" "${SLACK_CHANNEL}" "$message" "upload" "$ERROR_LOG_FILE"
}

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

end_time=$(TZ=Asia/Omsk date -v+60M "+%H:%M")
message=":hammer_and_wrench: MacOS build started on \`$BRANCH_NAME\` with $analyticsMessage analytics. It will be ready approximately at $end_time"
first_ts=$(post_message "${SLACK_BOT_TOKEN}" "${SLACK_CHANNEL}" "$message")
echo "first_ts=$first_ts"

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
git commit -m "add: MacOS version bump"
git push origin "$BRANCH_NAME"

rm -rf "$BUILD_PATH"

if [ "$isUseDevAnalytics" == "false" ]; then
  enable_prod_keys
  comment_desktop_build_native_lib

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

sleep 20

if [ ! -d "$BUILD_PATH" ]; then
  echo "Error: Signed Build not found at expected path: $BUILD_PATH"
  post_error_message "$BRANCH_NAME"
  exit 1
fi

echo "Built successfully: $BUILD_PATH"

# Rename ZIP file to Neuro.zip
ZIP_PATH="$PROJECT_DIR/desktopApp/build/compose/binaries/main/app/Neuro.zip"
echo "Creating ZIP file: $ZIP_PATH"
cd "$(dirname "$BUILD_PATH")" || exit 1
zip -r "$(basename "$ZIP_PATH")" "$(basename "$BUILD_PATH")"

if [ $? -eq 0 ]; then
  echo "ZIP file created successfully: $ZIP_PATH"
else
  post_error_message "$BRANCH_NAME"
  echo "Error creating ZIP file."
  exit 1
fi

## Notarization Section (Before triggering the build tool)
echo "Submitting build for notarization..."
xcrun notarytool submit "$ZIP_PATH" \
  --apple-id "$APPLE_ID" \
  --team-id "$TEAM_ID" \
  --password "$NOTARY_PASSWORD" \
  --wait

if [ $? -eq 0 ]; then
  echo "Notarization completed successfully."
else
  post_error_message "$BRANCH_NAME"
  echo "Error during notarization."
  exit 1
fi

sleep 20

open "$BUILD_TOOL"

sleep 5

PROCESS_NAME="Packages"

echo "Triggering cmd+B for $PROCESS_NAME..."

TIMEOUT=60
INTERVAL=10

echo "Triggering cmd+B for $PROCESS_NAME..."

trigger_build() {
  osascript <<EOF
  tell application "System Events"
    if exists application process "$PROCESS_NAME" then
      set frontmost of application process "$PROCESS_NAME" to true
      keystroke "b" using {command down}
    else
      error "Error: Could not find the process for $PROCESS_NAME. Verify the application name."
    end if
  end tell
EOF
}

trigger_build

echo "Waiting for notarized build to complete..."

NOTARIZED_BUILD_PATH="/Users/denispopkov/AndroidStudioProjects/SA_Neuro_release/build/Neuro_desktop.pkg"
elapsed_time=0
while [ ! -f "$NOTARIZED_BUILD_PATH" ]; do
  sleep $INTERVAL
  elapsed_time=$((elapsed_time + INTERVAL))
  echo "Checking for notarized build..."

  if [ $elapsed_time -ge $TIMEOUT ]; then
    echo "Build not found after $TIMEOUT seconds. Retrying..."
    trigger_build
    elapsed_time=0
  fi
done

sleep 20

# Sign the dylib
echo "Signing the libkeychainbridge.dylib..."
echo "$USER_PASSWORD" | sudo -S codesign --force --deep --options runtime --entitlements "$PROJECT_DIR/desktopApp/macos/entitlements/entitlements.plist" --sign "Developer ID Application: Source Audio LLC (Z2JAQC4DXV)" "$DYLIB_PATH"

## Signing the .pkg
SIGNED_PKG_PATH="/Users/denispopkov/AndroidStudioProjects/SA_Neuro_release/build/Neuro_desktopS.pkg"
echo "Signing the .pkg file..."
echo "$USER_PASSWORD" | sudo -S productsign --sign "Developer ID Installer: Source Audio LLC (Z2JAQC4DXV)" "$NOTARIZED_BUILD_PATH" "$SIGNED_PKG_PATH"

sleep 20

# Final Notarization of Signed .pkg
echo "Submitting the signed .pkg for notarization..."
xcrun notarytool submit "$SIGNED_PKG_PATH" \
  --apple-id "$APPLE_ID" \
  --team-id "$TEAM_ID" \
  --password "$NOTARY_PASSWORD" \
  --wait

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

# Check the signature of the renamed .pkg
echo "Checking signature of the renamed .pkg file..."
SIGNATURE_CHECK=$(pkgutil --check-signature "$NEW_PKG_PATH")

if [[ "$SIGNATURE_CHECK" == *"Developer ID Installer: Source Audio LLC"* ]]; then
  echo "Signature verified successfully!"
else
  post_error_message "$BRANCH_NAME"
  echo "Error: Signature verification failed."
  exit 1
fi

echo "Uploading renamed .pkg to Slack..."
execute_file_upload "${SLACK_BOT_TOKEN}" "${SLACK_CHANNEL}" ":white_check_mark: MacOS signed from \`$BRANCH_NAME\` with ${analyticsMessage} analytics" "upload" "${NEW_PKG_PATH}"

sleep 10

undo_enable_prod_keys

if [ $? -eq 0 ]; then
    echo "Renamed .pkg sent to Slack successfully."
else
    post_error_message "$BRANCH_NAME"
    echo "Error sending renamed .pkg to Slack."
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

pkill -f "$PROCESS_NAME"

if [ -f "$NOTARIZED_BUILD_PATH" ]; then
    echo "Removing notarized build file at $NOTARIZED_BUILD_PATH..."
    rm "$NOTARIZED_BUILD_PATH"
    echo "File removed successfully."
else
    echo "File not found: $NOTARIZED_BUILD_PATH"
fi

delete_message "${SLACK_BOT_TOKEN}" "${SLACK_CHANNEL}" "$first_ts"
