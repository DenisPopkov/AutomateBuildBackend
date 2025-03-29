#!/bin/bash

source "/Users/denispopkov/PycharmProjects/AutomateBuildBackend/slack_upload.sh"
source "/Users/denispopkov/PycharmProjects/AutomateBuildBackend/utils.sh"

SECRET_FILE="/Users/denispopkov/Desktop/secret.txt"
BUILD_TOOL="/Users/denispopkov/AndroidStudioProjects/SA_Neuro_release/Neuro_desktop.pkgproj"

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
SET_UPDATED_LIB_PATH="$PROJECT_DIR/shared/src/commonMain/resources/MR/files/libdspmac.dylib"
CACHE_UPDATED_LIB_PATH="$PROJECT_DIR/desktopApp/build/native/libdspmac.dylib"

# For dev analytics
SHARED_GRADLE_FILE="$PROJECT_DIR/shared/build.gradle.kts"
PROD_SHARED_GRADLE_FILE="/Users/denispopkov/Desktop/prod/build.gradle.kts"

if [ "$isUseDevAnalytics" == "false" ]; then
  echo "Replacing $SHARED_GRADLE_FILE with $PROD_SHARED_GRADLE_FILE"
  rm -f "$SHARED_GRADLE_FILE"
  cp "$PROD_SHARED_GRADLE_FILE" "$SHARED_GRADLE_FILE"
  else
    echo "Nothing to change with analytics"
fi

enable_dsp_gradle_task

sleep 5

osascript -e '
  tell application "System Events"
    tell process "Android Studio"
        keystroke "O" using {command down, shift down}
    end tell
  end tell
'

sleep 80

./gradlew compileKotlin

sleep 5

disable_dsp_gradle_task

rm -f "$SET_UPDATED_LIB_PATH"
cp "$CACHE_UPDATED_LIB_PATH" "$SET_UPDATED_LIB_PATH"

# Building
echo "Building signed build..."
./gradlew packageDmg

# Find the build
BUILD_PATH="$PROJECT_DIR/desktopApp/build/compose/binaries/main/app/Neuro Desktop.app"

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

# Rename signed .pkg to final format
BASE_NAME="neuro_desktop_${VERSION_NAME}-[${VERSION_CODE}]_installer_mac.pkg"
FINAL_DIR="/Users/denispopkov/Desktop/builds"
FINAL_PKG_PATH="$FINAL_DIR/$BASE_NAME"

# Check if the file already exists
if [ -f "$FINAL_PKG_PATH" ]; then
    echo "File with name $BASE_NAME already exists. Finding a unique name..."
    INDEX=1
    while [ -f "$FINAL_PKG_PATH" ]; do
        FINAL_PKG_PATH="$FINAL_DIR/neuro_desktop_${VERSION_NAME}-[${VERSION_CODE}]_installer_mac_${INDEX}.pkg"
        INDEX=$((INDEX + 1))
    done
fi

# Move the file to the builds folder with the final name
mv "$SIGNED_PKG_PATH" "$FINAL_PKG_PATH" || { echo "Error renaming .pkg"; exit 1; }
echo "Renamed .pkg and moved to: $FINAL_PKG_PATH"

# Check the signature of the renamed .pkg
echo "Checking signature of the renamed .pkg file..."
SIGNATURE_CHECK=$(pkgutil --check-signature "$FINAL_PKG_PATH")

if [[ "$SIGNATURE_CHECK" == *"Developer ID Installer: Source Audio LLC"* ]]; then
  echo "Signature verified successfully!"
else
  post_error_message "$BRANCH_NAME"
  echo "Error: Signature verification failed."
  exit 1
fi

echo "Uploading renamed .pkg to Slack..."
execute_file_upload "${SLACK_BOT_TOKEN}" "${SLACK_CHANNEL}" "macOS signed from $BRANCH_NAME" "upload" "${FINAL_PKG_PATH}"

sleep 10

echo "PKG sent to Slack successfully."
git pull origin "$BRANCH_NAME" --no-rebase
git stash push -m "Stashing build.gradle.kts" --keep-index -- "$PROJECT_DIR/shared/build.gradle.kts"
git add .
git commit -m "Update hardcoded libs"
git push origin "$BRANCH_NAME"

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
