#!/bin/bash

source "./slack_upload.sh"
source "./utils.sh"

BRANCH_NAME=$1
isUseDevAnalytics=$2

SECRET_FILE="/c/Users/BlackBricks/Desktop/secret.txt"
PROJECT_DIR="/c/Users/BlackBricks/StudioProjects/SA_Neuro_Multiplatform"
ERROR_LOG_FILE="${ERROR_LOG_FILE:-/tmp/build_error_log.txt}"
APP_DIR="/c/Users/BlackBricks/AppData/Local/Neuro Desktop"
ADVANCED_INSTALLER_CONFIG="/c/Users/BlackBricks/Applications/Neuro installer/installer_win/Neuro Desktop 2.aip"
ADVANCED_INSTALLER_SETUP_FILES="/c/Users/BlackBricks/Applications/Neuro installer/installer_win/Neuro Desktop-SetupFiles"
MSI_OUTPUT_DIR="$ADVANCED_INSTALLER_SETUP_FILES"

while IFS='=' read -r key value; do
  key=$(echo "$key" | xargs)
  value=$(echo "$value" | xargs)

  case "$key" in
    "SLACK_BOT_TOKEN") SLACK_BOT_TOKEN="$value" ;;
    "SLACK_CHANNEL") SLACK_CHANNEL="$value" ;;
  esac
done < "$SECRET_FILE"

post_error_message() {
  local branch_name=$1
  local message=":x: Failed to build Windows on \`$branch_name\`"
  execute_file_upload "${SLACK_BOT_TOKEN}" "${SLACK_CHANNEL}" "$message" "upload" "$ERROR_LOG_FILE"
}

cd "$PROJECT_DIR" || { echo "Project directory not found!"; exit 1; }

echo "Checking out branch: $BRANCH_NAME"
git stash push -m "Pre-build stash"
git fetch --all
git checkout "$BRANCH_NAME"
git pull origin "$BRANCH_NAME" --no-rebase

VERSION_CODE=$(grep '^desktop\.build\.number\s*=' "$PROJECT_DIR/gradle.properties" | sed 's/.*=\s*\([0-9]*\)/\1/' | xargs)
VERSION_NAME=$(grep '^desktop\.version\s*=' "$PROJECT_DIR/gradle.properties" | sed 's/.*=\s*\([0-9]*\.[0-9]*\.[0-9]*\)/\1/' | xargs)

VERSION_CODE=$((VERSION_CODE + 1))
sed -i "s/^desktop\.build\.number\s*=\s*[0-9]*$/desktop.build.number=$VERSION_CODE/" "$PROJECT_DIR/gradle.properties"
git pull origin "$BRANCH_NAME" --no-rebase
git add .
git commit -m "Windows version bump to $VERSION_CODE"
git push origin "$BRANCH_NAME"

analyticsMessage=""

if [ "$isUseDevAnalytics" == "true" ]; then
  analyticsMessage="dev"
else
  analyticsMessage="prod"
fi

end_time=$(date -d "+15 minutes" +"%H:%M")
message=":hammer_and_wrench: Windows build started on \`$BRANCH_NAME\` with $analyticsMessage analytics. It will be ready approximately at $end_time"
first_ts=$(post_message "${SLACK_BOT_TOKEN}" "${SLACK_CHANNEL}" "$message")

if [ "$isUseDevAnalytics" == "false" ]; then
  enable_prod_keys

  sleep 5

  powershell -command "\
  Add-Type -AssemblyName System.Windows.Forms; \
  [System.Windows.Forms.SendKeys]::SendWait('^(+o)')"

  sleep 50
else
  echo "Nothing to change with analytics"
fi

echo "Building MSI package..."
./gradlew packageReleaseMsi

DESKTOP_BUILD_PATH="$PROJECT_DIR/desktopApp/build/compose/binaries/main-release/msi"

MSI_FILE=$(find "$DESKTOP_BUILD_PATH" -name "Neuro*.msi" | head -n 1)

if [ -z "$MSI_FILE" ]; then
    echo "Error: No MSI file found in $DESKTOP_BUILD_PATH"
    post_error_message "$BRANCH_NAME"
    exit 1
fi

NEW_MSI_PATH="$DESKTOP_BUILD_PATH/Neuro_Desktop-${VERSION_NAME}-${VERSION_CODE}.msi"

if [ -f "$NEW_MSI_PATH" ]; then
    rm -f "$NEW_MSI_PATH"
    echo "Deleted existing file: $NEW_MSI_PATH"
fi

mv "$MSI_FILE" "$NEW_MSI_PATH"
echo "Renamed file to: $NEW_MSI_PATH"

rm -rf "$ADVANCED_INSTALLER_SETUP_FILES/app" "$ADVANCED_INSTALLER_SETUP_FILES/realtime"
cp -r "$APP_DIR/app" "$ADVANCED_INSTALLER_SETUP_FILES/"
cp -r "$APP_DIR/realtime" "$ADVANCED_INSTALLER_SETUP_FILES/"

OLD_VERSION=$(grep -oP 'Property Id="ProductVersion" Value="\K[^"]+' "$ADVANCED_INSTALLER_CONFIG")
sed -i "s/Property Id=\"ProductVersion\" Value=\"$OLD_VERSION\"/Property Id=\"ProductVersion\" Value=\"$VERSION_NAME\"/" "$ADVANCED_INSTALLER_CONFIG"

echo "Building with Advanced Installer..."
"/c/Users/BlackBricks/Applications/Neuro installer/installer_win/AdvancedInstaller.com" /build "$ADVANCED_INSTALLER_CONFIG"

MSI_FILE_PATH="$MSI_OUTPUT_DIR/Neuro_Desktop-${VERSION_NAME}-${VERSION_CODE}.msi"
echo "Uploading MSI to Slack..."
execute_file_upload "${SLACK_BOT_TOKEN}" "${SLACK_CHANNEL}" ":white_check_mark: Windows build for \`$BRANCH_NAME\`" "upload" "$MSI_FILE_PATH"

#powershell -command "signtool sign /fd sha256 /tr http://ts.ssl.com /td sha256 /sha1 20fbd34014857033bcc6dabfae390411b22b0b1e \"$MSI_FILE_PATH\""

delete_message "${SLACK_BOT_TOKEN}" "${SLACK_CHANNEL}" "$first_ts"
