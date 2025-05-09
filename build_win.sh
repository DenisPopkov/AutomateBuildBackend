#!/bin/bash

source "./slack_upload.sh"
source "./utils.sh"

BRANCH_NAME=$1
isUseDevAnalytics=$2

SECRET_FILE="/c/Users/BlackBricks/Desktop/secret.txt"
PROJECT_DIR="/c/Users/BlackBricks/StudioProjects/SA_Neuro_Multiplatform"
ERROR_LOG_FILE="${ERROR_LOG_FILE:-/tmp/build_error_log.txt}"
ADVANCED_INSTALLER_CONFIG="/c/Users/BlackBricks/Applications/Neuro installer/installer_win/Neuro Desktop 2.aip"
ADVANCED_INSTALLER_SETUP_FILES="/c/Users/BlackBricks/Applications/Neuro installer"
ADVANCED_INSTALLER_MSI_FILES="/c/Users/BlackBricks/Applications/Neuro installer/installer_win/Neuro Desktop-SetupFiles"

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
  execute_file_upload "$SLACK_BOT_TOKEN" "$SLACK_CHANNEL" "$message" "upload" "$ERROR_LOG_FILE"
}

cd "$PROJECT_DIR" || exit 1
#git stash push -m "Pre-build stash"
#git fetch --all
#git checkout "$BRANCH_NAME"
#git pull origin "$BRANCH_NAME" --no-rebase

VERSION_CODE=$(grep '^desktop\.build\.number\s*=' gradle.properties | sed 's/.*=\s*\([0-9]*\)/\1/' | xargs)
VERSION_NAME=$(grep '^desktop\.version\s*=' gradle.properties | sed 's/.*=\s*\([0-9]*\.[0-9]*\.[0-9]*\)/\1/' | xargs)
#VERSION_CODE=$((VERSION_CODE + 1))
#
#sed -i "s/^desktop\.build\.number\s*=\s*[0-9]*$/desktop.build.number=$VERSION_CODE/" gradle.properties
#git add gradle.properties
#git commit -m "Windows version bump to $VERSION_CODE"
#git push origin "$BRANCH_NAME"

analyticsMessage="prod"
[ "$isUseDevAnalytics" == "true" ] && analyticsMessage="dev"

#end_time=$(date -d "+15 minutes" +"%H:%M")
#message=":hammer_and_wrench: Windows build started on \`$BRANCH_NAME\` with $analyticsMessage analytics. It will be ready approximately at $end_time"
#first_ts=$(post_message "$SLACK_BOT_TOKEN" "$SLACK_CHANNEL" "$message")

if [ "$isUseDevAnalytics" == "false" ]; then
  enable_prod_keys
  sleep 5
  powershell -command "Add-Type -AssemblyName System.Windows.Forms; [System.Windows.Forms.SendKeys]::SendWait('^(+o)')"
  sleep 50
fi

./gradlew packageReleaseMsi || { post_error_message "$BRANCH_NAME"; exit 1; }

DESKTOP_BUILD_PATH="$PROJECT_DIR/desktopApp/build/compose/binaries/main-release/msi"
MSI_FILE=$(find "$DESKTOP_BUILD_PATH" -name "Neuro*.msi" | head -n 1)
[ -z "$MSI_FILE" ] && { post_error_message "$BRANCH_NAME"; exit 1; }

NEW_MSI_PATH="$DESKTOP_BUILD_PATH/Neuro_Desktop-${VERSION_NAME}-${VERSION_CODE}.msi"
[ -f "$NEW_MSI_PATH" ] && rm -f "$NEW_MSI_PATH"
mv "$MSI_FILE" "$NEW_MSI_PATH"
echo "Moving MSI: $MSI_FILE -> $NEW_MSI_PATH"

LESSMSI_EXE="/c/ProgramData/chocolatey/bin/lessmsi.exe"
"$LESSMSI_EXE" x "$NEW_MSI_PATH" > /tmp/lessmsi_extract.log 2>&1

if ! grep -q "Extracting" /tmp/lessmsi_extract.log; then
  printf "Error: lessmsi failed to extract MSI\n" >&2
  post_error_message "$BRANCH_NAME"
  exit 1
fi

export LESSMSI_EXTRACT_DIR_WIN="C:\\Users\\BlackBricks\\Neuro_Desktop-${VERSION_NAME}-${VERSION_CODE}"

TEMP_EXTRACTED_NAME="Neuro_Desktop-${VERSION_NAME}-${VERSION_CODE}"
USER_HOME_MSI_EXTRACT_PATH="/c/Users/BlackBricks/$TEMP_EXTRACTED_NAME"
MSI_EXTRACT_DIR="$ADVANCED_INSTALLER_MSI_FILES/$TEMP_EXTRACTED_NAME"

[ ! -d "$USER_HOME_MSI_EXTRACT_PATH" ] && {
  printf "Error: MSI extracted directory not found at %s\n" "$USER_HOME_MSI_EXTRACT_PATH" >&2
  post_error_message "$BRANCH_NAME"
  exit 1
}

echo "Moving extracted MSI folder: $USER_HOME_MSI_EXTRACT_PATH -> $MSI_EXTRACT_DIR"
rm -rf "$MSI_EXTRACT_DIR"
mv "$USER_HOME_MSI_EXTRACT_PATH" "$MSI_EXTRACT_DIR"

EXTRACTED_APP_PATH="$MSI_EXTRACT_DIR/SourceDir/Neuro Desktop"
echo "Extracted app path: $EXTRACTED_APP_PATH"
[ ! -d "$EXTRACTED_APP_PATH" ] && { post_error_message "$BRANCH_NAME"; exit 1; }

echo "Cleaning old app and realtime folders"
rm -rf "$ADVANCED_INSTALLER_SETUP_FILES/app"
rm -rf "$ADVANCED_INSTALLER_SETUP_FILES/realtime"

echo "Copying app and realtime from extracted MSI to setup files"
cp -r "$EXTRACTED_APP_PATH/app" "$ADVANCED_INSTALLER_SETUP_FILES/" || {
  printf "Error: Failed to copy 'app' directory\n" >&2
  post_error_message "$BRANCH_NAME"
  exit 1
}

if [ -d "$EXTRACTED_APP_PATH/realtime" ]; then
  cp -r "$EXTRACTED_APP_PATH/realtime" "$ADVANCED_INSTALLER_SETUP_FILES/"
else
  printf "Warning: 'realtime' folder not found, skipping\n" >&2
fi

OLD_VERSION=$(sed -n 's/.*Property Id="ProductVersion" Value="\([^"]*\)".*/\1/p' "$ADVANCED_INSTALLER_CONFIG")
sed -i "s/Property Id=\"ProductVersion\" Value=\"$OLD_VERSION\"/Property Id=\"ProductVersion\" Value=\"$VERSION_NAME\"/" "$ADVANCED_INSTALLER_CONFIG"

GENERATE_CODE=$(sed -n 's/.*Property Id="GenerateCode" Value="\([^"]*\)".*/\1/p' "$ADVANCED_INSTALLER_CONFIG")
NEXT_GENERATE_CODE=$((GENERATE_CODE + 1))
sed -i "s/Property Id=\"GenerateCode\" Value=\"$GENERATE_CODE\"/Property Id=\"GenerateCode\" Value=\"$NEXT_GENERATE_CODE\"/" "$ADVANCED_INSTALLER_CONFIG"

echo "Building installer from $ADVANCED_INSTALLER_CONFIG"
cmd.exe /c "\"C:\\Program Files (x86)\\Caphyon\\Advanced Installer 20.6\\bin\\x86\\AdvancedInstaller.com\" /build \"$ADVANCED_INSTALLER_CONFIG\""

#SIGNED_MSI_PATH="$ADVANCED_INSTALLER_MSI_FILES/Neuro_Desktop-${VERSION_NAME}-${VERSION_CODE}.msi"
# signtool sign /fd sha256 /tr http://ts.ssl.com /td sha256 /sha1 20fbd34014857033bcc6dabfae390411b22b0b1e "$SIGNED_MSI_PATH"

#echo "Uploading signed MSI to Slack: $SIGNED_MSI_PATH"
#execute_file_upload "$SLACK_BOT_TOKEN" "$SLACK_CHANNEL" ":white_check_mark: Windows build for \`$BRANCH_NAME\`" "upload" "$SIGNED_MSI_PATH"
#delete_message "$SLACK_BOT_TOKEN" "$SLACK_CHANNEL" "$first_ts"
