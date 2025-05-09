#!/bin/bash

source "./slack_upload.sh"
source "./utils.sh"

BRANCH_NAME=$1
isUseDevAnalytics=$2

SECRET_FILE="/c/Users/BlackBricks/Desktop/secret.txt"
PROJECT_DIR="/c/Users/BlackBricks/StudioProjects/SA_Neuro_Multiplatform"
ERROR_LOG_FILE="${ERROR_LOG_FILE:-/tmp/build_error_log.txt}"
ADVANCED_INSTALLER_CONFIG="/c/Users/BlackBricks/Applications/Neuro installer/installer_win/Neuro Desktop 2.aip"
ADVANCED_INSTALLER_SETUP_FILES="/c/Users/BlackBricks/Applications/Neuro installer/installer_win/Neuro Desktop-SetupFiles"

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
git stash push -m "Pre-build stash"
git fetch --all
git checkout "$BRANCH_NAME"
git pull origin "$BRANCH_NAME" --no-rebase

VERSION_CODE=$(grep '^desktop\.build\.number\s*=' gradle.properties | sed 's/.*=\s*\([0-9]*\)/\1/' | xargs)
VERSION_NAME=$(grep '^desktop\.version\s*=' gradle.properties | sed 's/.*=\s*\([0-9]*\.[0-9]*\.[0-9]*\)/\1/' | xargs)
VERSION_CODE=$((VERSION_CODE + 1))

sed -i "s/^desktop\.build\.number\s*=\s*[0-9]*$/desktop.build.number=$VERSION_CODE/" gradle.properties
git add gradle.properties
git commit -m "Windows version bump to $VERSION_CODE"
git push origin "$BRANCH_NAME"

analyticsMessage="prod"
[ "$isUseDevAnalytics" == "true" ] && analyticsMessage="dev"

end_time=$(date -d "+15 minutes" +"%H:%M")
message=":hammer_and_wrench: Windows build started on \`$BRANCH_NAME\` with $analyticsMessage analytics. It will be ready approximately at $end_time"
first_ts=$(post_message "$SLACK_BOT_TOKEN" "$SLACK_CHANNEL" "$message")

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

EXTRACT_DIR="$PROJECT_DIR/Neuro_Desktop-${VERSION_NAME}-${VERSION_CODE}"
/c/ProgramData/chocolatey/bin/lessmsi.exe x "$NEW_MSI_PATH" "$EXTRACT_DIR"

EXTRACTED_APP_PATH="$EXTRACT_DIR/SourceDir/ProgramFilesFolder/Source Audio/Neuro Desktop 3"
[ ! -d "$EXTRACTED_APP_PATH" ] && { post_error_message "$BRANCH_NAME"; exit 1; }

rm -rf "$ADVANCED_INSTALLER_SETUP_FILES/app" "$ADVANCED_INSTALLER_SETUP_FILES/realtime"
cp -r "$EXTRACTED_APP_PATH/app" "$ADVANCED_INSTALLER_SETUP_FILES/"
cp -r "$EXTRACTED_APP_PATH/realtime" "$ADVANCED_INSTALLER_SETUP_FILES/"

OLD_VERSION=$(grep -oP 'Property Id="ProductVersion" Value="\K[^"]+' "$ADVANCED_INSTALLER_CONFIG")
sed -i "s/Property Id=\"ProductVersion\" Value=\"$OLD_VERSION\"/Property Id=\"ProductVersion\" Value=\"$VERSION_NAME\"/" "$ADVANCED_INSTALLER_CONFIG"

GENERATE_CODE=$(grep -oP 'Property Id="GenerateCode" Value="\K[^"]+' "$ADVANCED_INSTALLER_CONFIG")
NEXT_GENERATE_CODE=$((GENERATE_CODE + 1))
sed -i "s/Property Id=\"GenerateCode\" Value=\"$GENERATE_CODE\"/Property Id=\"GenerateCode\" Value=\"$NEXT_GENERATE_CODE\"/" "$ADVANCED_INSTALLER_CONFIG"

powershell -Command "Start-Process -Wait -NoNewWindow 'C:/Program Files (x86)/Caphyon/Advanced Installer 20.6/bin/x86/AdvancedInstaller.exe' -ArgumentList '/build', '$ADVANCED_INSTALLER_CONFIG'"

SIGNED_MSI_PATH="$ADVANCED_INSTALLER_SETUP_FILES/Neuro_Desktop-${VERSION_NAME}-${VERSION_CODE}.msi"
# signtool sign /fd sha256 /tr http://ts.ssl.com /td sha256 /sha1 20fbd34014857033bcc6dabfae390411b22b0b1e "$SIGNED_MSI_PATH"

execute_file_upload "$SLACK_BOT_TOKEN" "$SLACK_CHANNEL" ":white_check_mark: Windows build for \`$BRANCH_NAME\`" "upload" "$SIGNED_MSI_PATH"
delete_message "$SLACK_BOT_TOKEN" "$SLACK_CHANNEL" "$first_ts"
