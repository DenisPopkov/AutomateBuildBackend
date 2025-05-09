#!/bin/bash

source "./slack_upload.sh"
source "./utils.sh"

BRANCH_NAME=$1
isUseDevAnalytics=$2

SECRET_FILE="/c/Users/BlackBricks/Desktop/secret.txt"
ERROR_LOG_FILE="${ERROR_LOG_FILE:-/tmp/build_error_log.txt}"
PROJECT_DIR="/c/Users/BlackBricks/StudioProjects/SA_Neuro_Multiplatform"
ADV_INST_CONFIG="/c/Users/BlackBricks/Applications/Neuro installer/installer_win/Neuro Desktop 2.aip"
ADV_INST_SETUP_FILES="/c/Users/BlackBricks/Applications/Neuro installer"
ADV_INST_COM="/c/Program Files (x86)/Caphyon/Advanced Installer 22.6/bin/x86/AdvancedInstaller.com"
ADVANCED_INSTALLER_MSI_FILES="/c/Users/BlackBricks/Applications/Neuro installer/installer_win/Neuro Desktop-SetupFiles"

#
#while IFS='=' read -r key value; do
#  key=$(echo "$key" | xargs)
#  value=$(echo "$value" | xargs)
#  case "$key" in
#    "SLACK_BOT_TOKEN") SLACK_BOT_TOKEN="$value" ;;
#    "SLACK_CHANNEL") SLACK_CHANNEL="$value" ;;
#  esac
#done < "$SECRET_FILE"
#
#post_error_message() {
#  local branch_name=$1
#  local message=":x: Failed to build Windows on \`$branch_name\`"
#  execute_file_upload "$SLACK_BOT_TOKEN" "$SLACK_CHANNEL" "$message" "upload" "$ERROR_LOG_FILE"
#}
#
cd "$PROJECT_DIR" || exit 1
##git stash push -m "Pre-build stash"
##git fetch --all
##git checkout "$BRANCH_NAME"
##git pull origin "$BRANCH_NAME" --no-rebase
#
VERSION_CODE=$(grep '^desktop\.build\.number\s*=' gradle.properties | sed 's/.*=\s*\([0-9]*\)/\1/' | xargs)
VERSION_NAME=$(grep '^desktop\.version\s*=' gradle.properties | sed 's/.*=\s*\([0-9]*\.[0-9]*\.[0-9]*\)/\1/' | xargs)
##VERSION_CODE=$((VERSION_CODE + 1))
##
##sed -i "s/^desktop\.build\.number\s*=\s*[0-9]*$/desktop.build.number=$VERSION_CODE/" gradle.properties
##git add gradle.properties
##git commit -m "Windows version bump to $VERSION_CODE"
##git push origin "$BRANCH_NAME"
#
#analyticsMessage="prod"
#[ "$isUseDevAnalytics" == "true" ] && analyticsMessage="dev"
#
##end_time=$(date -d "+15 minutes" +"%H:%M")
##message=":hammer_and_wrench: Windows build started on \`$BRANCH_NAME\` with $analyticsMessage analytics. It will be ready approximately at $end_time"
##first_ts=$(post_message "$SLACK_BOT_TOKEN" "$SLACK_CHANNEL" "$message")
#
#if [ "$isUseDevAnalytics" == "false" ]; then
#  enable_prod_keys
#  sleep 5
#  powershell -command "Add-Type -AssemblyName System.Windows.Forms; [System.Windows.Forms.SendKeys]::SendWait('^(+o)')"
#  sleep 50
#fi
#
#./gradlew packageReleaseMsi || { post_error_message "$BRANCH_NAME"; exit 1; }

DESKTOP_BUILD_PATH="$PROJECT_DIR/desktopApp/build/compose/binaries/main-release/msi"
MSI_FILE=$(find "$DESKTOP_BUILD_PATH" -name "Neuro*.msi" | head -n 1)
[ -z "$MSI_FILE" ] && { echo "[ERROR] MSI file not found"; post_error_message "$BRANCH_NAME"; exit 1; }

NEW_MSI_PATH="$DESKTOP_BUILD_PATH/Neuro_Desktop-${VERSION_NAME}-${VERSION_CODE}.msi"
[ -f "$NEW_MSI_PATH" ] && rm -f "$NEW_MSI_PATH"
mv "$MSI_FILE" "$NEW_MSI_PATH" || { echo "[ERROR] Failed to rename MSI"; exit 1; }

echo "[INFO] Extracting MSI..."
/c/ProgramData/chocolatey/bin/lessmsi.exe x "$NEW_MSI_PATH" || { echo "[ERROR] Failed to extract MSI"; exit 1; }

sleep 10

EXTRACT_DIR="/c/Users/BlackBricks/StudioProjects/SA_Neuro_Multiplatform/Neuro_Desktop-${VERSION_NAME}-${VERSION_CODE}/SourceDir/Neuro Desktop"

echo "[INFO] Removing old app and runtime folders..."
rm -rf "${ADV_INST_SETUP_FILES}/app"
rm -rf "${ADV_INST_SETUP_FILES}/runtime"

echo "[INFO] Copying new app and runtime folders..."
cp -r "${EXTRACT_DIR}/app" "${ADV_INST_SETUP_FILES}/" || { echo "[ERROR] Failed to copy 'app' folder"; exit 1; }
cp -r "${EXTRACT_DIR}/runtime" "${ADV_INST_SETUP_FILES}/" || { echo "[ERROR] Failed to copy 'runtime' folder"; exit 1; }

echo "[INFO] Updating version and product code..."
sed -i "s/\(Property=\"ProductVersion\" Value=\"\)[^\"]*\(\".*\)/\1${VERSION_NAME}\2/" "$ADV_INST_CONFIG"
NEW_GUID=$(powershell.exe "[guid]::NewGuid().ToString()" | tr -d '\r')
[ -z "$NEW_GUID" ] && { echo "[ERROR] Failed to generate ProductCode"; exit 1; }
sed -i "s/\(Property=\"ProductCode\" Value=\"\)[^\"]*\(\".*\)/\1${NEW_GUID}\2/" "$ADV_INST_CONFIG"
sed -i "s/\(PackageFileName=\"Neuro_Desktop-\)[^\"]*\(\".*\)/\1${VERSION_NAME}-${VERSION_CODE}\2/" "$ADV_INST_CONFIG"

echo "[INFO] Backing up .aip..."
cp "$ADV_INST_CONFIG" "${ADV_INST_CONFIG}.bak" || { echo "[ERROR] Failed to backup .aip"; exit 1; }

echo "[INFO] Cleaning .aip from all references to app/runtime..."
echo "[DEBUG] Checking for xmlstarlet..." >> cleanup.log
XMLSTARLET_PATH=$(command -v xmlstarlet || command -v xmlstarlet.exe || echo "C:/ProgramData/chocolatey/bin/xmlstarlet.exe")
if [ ! -x "$XMLSTARLET_PATH" ]; then
    echo "[ERROR] xmlstarlet is not installed or not executable. Please ensure it is installed using 'choco install xmlstarlet' and available in PATH."
    echo "[DEBUG] XMLSTARLET_PATH=$XMLSTARLET_PATH" >> cleanup.log
    exit 1
fi
echo "[DEBUG] xmlstarlet found at: $XMLSTARLET_PATH" >> cleanup.log

# Удаление директорий, связанных с app и runtime
echo "[DEBUG] Removing app and runtime directories..." >> cleanup.log
"$XMLSTARLET_PATH" ed -d '//ROW[contains(@Directory, "app")]' "$ADV_INST_CONFIG" > "${ADV_INST_CONFIG}.tmp" && mv "${ADV_INST_CONFIG}.tmp" "$ADV_INST_CONFIG" || { echo "[ERROR] Failed to remove app directories"; exit 1; }
"$XMLSTARLET_PATH" ed -d '//ROW[contains(@Directory, "runtime")]' "$ADV_INST_CONFIG" > "${ADV_INST_CONFIG}.tmp" && mv "${ADV_INST_CONFIG}.tmp" "$ADV_INST_CONFIG" || { echo "[ERROR] Failed to remove runtime directories"; exit 1; }
"$XMLSTARLET_PATH" ed -d '//ROW[contains(@Directory_Parent, "app")]' "$ADV_INST_CONFIG" > "${ADV_INST_CONFIG}.tmp" && mv "${ADV_INST_CONFIG}.tmp" "$ADV_INST_CONFIG" || { echo "[ERROR] Failed to remove app parent directories"; exit 1; }
"$XMLSTARLET_PATH" ed -d '//ROW[contains(@Directory_Parent, "runtime")]' "$ADV_INST_CONFIG" > "${ADV_INST_CONFIG}.tmp" && mv "${ADV_INST_CONFIG}.tmp" "$ADV_INST_CONFIG" || { echo "[ERROR] Failed to remove runtime parent directories"; exit 1; }
"$XMLSTARLET_PATH" ed -d '//ROW[contains(@Directory_, "app")]' "$ADV_INST_CONFIG" > "${ADV_INST_CONFIG}.tmp" && mv "${ADV_INST_CONFIG}.tmp" "$ADV_INST_CONFIG" || { echo "[ERROR] Failed to remove app directory references"; exit 1; }
"$XMLSTARLET_PATH" ed -d '//ROW[contains(@Directory_, "runtime")]' "$ADV_INST_CONFIG" > "${ADV_INST_CONFIG}.tmp" && mv "${ADV_INST_CONFIG}.tmp" "$ADV_INST_CONFIG" || { echo "[ERROR] Failed to remove runtime directory references"; exit 1; }

# Удаление компонентов, связанных с app и runtime
echo "[DEBUG] Removing app and runtime components..." >> cleanup.log
"$XMLSTARLET_PATH" ed -d '//ROW[contains(@Component, "app")]' "$ADV_INST_CONFIG" > "${ADV_INST_CONFIG}.tmp" && mv "${ADV_INST_CONFIG}.tmp" "$ADV_INST_CONFIG" || { echo "[ERROR] Failed to remove app components"; exit 1; }
"$XMLSTARLET_PATH" ed -d '//ROW[contains(@Component, "runtime")]' "$ADV_INST_CONFIG" > "${ADV_INST_CONFIG}.tmp" && mv "${ADV_INST_CONFIG}.tmp" "$ADV_INST_CONFIG" || { echo "[ERROR] Failed to remove runtime components"; exit 1; }
"$XMLSTARLET_PATH" ed -d '//ROW[contains(@Component_, "app")]' "$ADV_INST_CONFIG" > "${ADV_INST_CONFIG}.tmp" && mv "${ADV_INST_CONFIG}.tmp" "$ADV_INST_CONFIG" || { echo "[ERROR] Failed to remove app component references"; exit 1; }
"$XMLSTARLET_PATH" ed -d '//ROW[contains(@Component_, "runtime")]' "$ADV_INST_CONFIG" > "${ADV_INST_CONFIG}.tmp" && mv "${ADV_INST_CONFIG}.tmp" "$ADV_INST_CONFIG" || { echo "[ERROR] Failed to remove runtime component references"; exit 1; }

# Удаление файлов, связанных с app и runtime
echo "[DEBUG] Removing app and runtime files..." >> cleanup.log
"$XMLSTARLET_PATH" ed -d '//ROW[contains(@File, "app")]' "$ADV_INST_CONFIG" > "${ADV_INST_CONFIG}.tmp" && mv "${ADV_INST_CONFIG}.tmp" "$ADV_INST_CONFIG" || { echo "[ERROR] Failed to remove app files"; exit 1; }
"$XMLSTARLET_PATH" ed -d '//ROW[contains(@File, "runtime")]' "$ADV_INST_CONFIG" > "${ADV_INST_CONFIG}.tmp" && mv "${ADV_INST_CONFIG}.tmp" "$ADV_INST_CONFIG" || { echo "[ERROR] Failed to remove runtime files"; exit 1; }
"$XMLSTARLET_PATH" ed -d '//ROW[contains(@SourcePath, "app")]' "$ADV_INST_CONFIG" > "${ADV_INST_CONFIG}.tmp" && mv "${ADV_INST_CONFIG}.tmp" "$ADV_INST_CONFIG" || { echo "[ERROR] Failed to remove app SourcePath"; exit 1; }
"$XMLSTARLET_PATH" ed -d '//ROW[contains(@SourcePath, "runtime")]' "$ADV_INST_CONFIG" > "${ADV_INST_CONFIG}.tmp" && mv "${ADV_INST_CONFIG}.tmp" "$ADV_INST_CONFIG" || { echo "[ERROR] Failed to remove runtime SourcePath"; exit 1; }

echo "[INFO] Verifying cleanup..."
grep -q 'app.*_Dir' "$ADV_INST_CONFIG" && { echo "[ERROR] Residual app_Dir found"; exit 1; }
grep -q 'runtime.*_Dir' "$ADV_INST_CONFIG" && { echo "[ERROR] Residual runtime_Dir found"; exit 1; }
grep -q 'SourcePath=".*app' "$ADV_INST_CONFIG" && { echo "[ERROR] Residual app SourcePath found"; exit 1; }
grep -q 'SourcePath=".*runtime' "$ADV_INST_CONFIG" && { echo "[ERROR] Residual runtime SourcePath found"; exit 1; }

echo "[INFO] Attempting to remove old folders via AdvancedInstaller CLI..."
cmd.exe /C "\"$ADV_INST_COM\" /edit \"$ADV_INST_CONFIG\" /DelFolder -path APPDIR\\app" || echo "[WARN] Could not delete APPDIR\\app"
cmd.exe /C "\"$ADV_INST_COM\" /edit \"$ADV_INST_CONFIG\" /DelFolder -path APPDIR\\runtime" || echo "[WARN] Could not delete APPDIR\\runtime"

echo "[INFO] Adding new app and runtime folders to .aip..."
if [ ! -d "${ADV_INST_SETUP_FILES}/app" ]; then
    echo "[ERROR] Folder ${ADV_INST_SETUP_FILES}/app does not exist"
    exit 1
fi
if [ ! -d "${ADV_INST_SETUP_FILES}/runtime" ]; then
    echo "[ERROR] Folder ${ADV_INST_SETUP_FILES}/runtime does not exist"
    exit 1
fi
echo "[DEBUG] Adding app folder: ${ADV_INST_SETUP_FILES}/app" >> cleanup.log
cmd.exe /C "\"$ADV_INST_COM\" /edit \"$ADV_INST_CONFIG\" /AddFolder -path APPDIR\\app -source \"$ADV_INST_SETUP_FILES\\app\"" || { echo "[ERROR] Failed to add app folder"; exit 1; }
echo "[DEBUG] Adding runtime folder: ${ADV_INST_SETUP_FILES}/runtime" >> cleanup.log
cmd.exe /C "\"$ADV_INST_COM\" /edit \"$ADV_INST_CONFIG\" /AddFolder -path APPDIR\\runtime -source \"$ADV_INST_SETUP_FILES\\runtime\"" || { echo "[ERROR] Failed to add runtime folder"; exit 1; }

echo "[INFO] Building installer..."
cmd.exe /C "\"$ADV_INST_COM\" /build \"$ADV_INST_CONFIG\"" || { echo "[ERROR] Build failed"; exit 1; }

#SIGNED_MSI_PATH="$ADVANCED_INSTALLER_MSI_FILES/Neuro_Desktop-${VERSION_NAME}-${VERSION_CODE}.msi"
# signtool sign /fd sha256 /tr http://ts.ssl.com /td sha256 /sha1 20fbd34014857033bcc6dabfae390411b22b0b1e "$SIGNED_MSI_PATH"

#echo "Uploading signed MSI to Slack: $SIGNED_MSI_PATH"
#execute_file_upload "$SLACK_BOT_TOKEN" "$SLACK_CHANNEL" ":white_check_mark: Windows build for \`$BRANCH_NAME\`" "upload" "$SIGNED_MSI_PATH"
#delete_message "$SLACK_BOT_TOKEN" "$SLACK_CHANNEL" "$first_ts"

echo "[INFO] Build completed successfully!"