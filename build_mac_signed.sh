#!/bin/bash

source "/Users/denispopkov/PycharmProjects/AutomateBuildBackend/slack_upload.sh"

SECRET_FILE="/Users/denispopkov/Desktop/secret.txt"
BUILD_TOOL="/Users/denispopkov/AndroidStudioProjects/SA_Neuro_release/Neuro_desktop.pkgproj"

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
    "TEAM_ID") TEAM_ID="$value" ;;
    "APPLE_ID") APPLE_ID="$value" ;;
    "NOTARY_PASSWORD") NOTARY_PASSWORD="$value" ;;
    "USER_PASSWORD") USER_PASSWORD="$value" ;;
  esac
done < "$SECRET_FILE"

if [ -z "$TEAM_ID" ] || [ -z "$APPLE_ID" ] || [ -z "$NOTARY_PASSWORD" ] || [ -z "$USER_PASSWORD" ]; then
  echo "Error: TEAM_ID, APPLE_ID, NOTARY_PASSWORD, or USER_PASSWORD is missing in $SECRET_FILE"
  exit 1
fi

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

# Extract versionCode and versionName from gradle.properties
VERSION_CODE=$(grep '^desktop\.version\s*=' "$PROJECT_DIR/gradle.properties" | sed 's/.*=\s*\(.*\)/\1/' | xargs)
VERSION_NAME=$(grep '^desktop\.build\.number\s*=' "$PROJECT_DIR/gradle.properties" | sed 's/.*=\s*"\(.*\)"/\1/' | xargs)

if [ -z "$VERSION_CODE" ] || [ -z "$VERSION_NAME" ]; then
  echo "Error: Unable to extract versionCode or versionName from gradle.properties"
  exit 1
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

# Rename ZIP file to Neuro.zip
ZIP_PATH="$PROJECT_DIR/desktopApp/build/compose/binaries/main/app/Neuro.zip"
echo "Creating ZIP file: $ZIP_PATH"
cd "$(dirname "$BUILD_PATH")" || exit 1
zip -r "$(basename "$ZIP_PATH")" "$(basename "$BUILD_PATH")"

if [ $? -eq 0 ]; then
  echo "ZIP file created successfully: $ZIP_PATH"
else
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
  echo "Error during notarization."
  exit 1
fi

# Open the build tool and trigger cmd+B
echo "Opening build tool..."
open "$BUILD_TOOL"

# Wait for the app to load (adjust the sleep duration as needed)
sleep 5

# Explicitly use the known process name (replace "Packages" with the actual name from Activity Monitor)
PROCESS_NAME="Packages"  # Adjust this to match the name you see in Activity Monitor

echo "Triggering cmd+B for $PROCESS_NAME..."

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

# Wait for the notarized build process to complete (adjust the sleep duration as needed)
echo "Waiting for notarized build to complete..."
NOTARIZED_BUILD_PATH="/Users/denispopkov/AndroidStudioProjects/SA_Neuro_release/build/Neuro_desktop.pkg"
while [ ! -f "$NOTARIZED_BUILD_PATH" ]; do
  sleep 10
  echo "Checking for notarized build..."
done

echo "Notarized build created successfully: $NOTARIZED_BUILD_PATH"

## Signing the .pkg
SIGNED_PKG_PATH="/Users/denispopkov/AndroidStudioProjects/SA_Neuro_release/build/Neuro_desktopS.pkg"
echo "Signing the .pkg file..."
echo "$USER_PASSWORD" | sudo -S productsign --sign "Developer ID Installer: Source Audio LLC (Z2JAQC4DXV)" "$NOTARIZED_BUILD_PATH" "$SIGNED_PKG_PATH"

if [ $? -eq 0 ]; then
  echo "Notarized .pkg file signed successfully: $SIGNED_PKG_PATH"
else
  echo "Error signing .pkg file."
  exit 1
fi

# Final Notarization of Signed .pkg
echo "Submitting the signed .pkg for notarization..."
xcrun notarytool submit "$SIGNED_PKG_PATH" \
  --apple-id "$APPLE_ID" \
  --team-id "$TEAM_ID" \
  --password "$NOTARY_PASSWORD" \
  --wait

if [ $? -eq 0 ]; then
  echo "Notarization of signed .pkg completed successfully."
else
  echo "Error during notarization of signed .pkg."
  exit 1
fi

# Rename signed .pkg to final format
RENAMED_PKG="/Users/denispopkov/Desktop/builds/neuro_desktop_${VERSION_CODE}_installer_mac.pkg"
mv "$SIGNED_PKG_PATH" "$RENAMED_PKG" || { echo "Error renaming .pkg"; exit 1; }
echo "Renamed .pkg and moved to: $RENAMED_PKG"

# Check the signature of the renamed .pkg
echo "Checking signature of the renamed .pkg file..."
SIGNATURE_CHECK=$(pkgutil --check-signature "$RENAMED_PKG")

if [[ "$SIGNATURE_CHECK" == *"Developer ID Installer: Source Audio LLC"* ]]; then
  echo "Signature verified successfully!"
else
  echo "Error: Signature verification failed."
  exit 1
fi

# Upload Renamed .pkg to Slack
echo "Uploading renamed .pkg to Slack..."
execute_file_upload "${SLACK_BOT_TOKEN}" "${SLACK_CHANNEL}" "macOS signed from $BRANCH_NAME" "${RENAMED_PKG}"

if [ $? -eq 0 ]; then
    echo "Renamed .pkg sent to Slack successfully."
else
    echo "Error sending renamed .pkg to Slack."
    exit 1
fi
