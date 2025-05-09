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

ADVANCED_INSTALLER="/c/Program Files (x86)/Caphyon/Advanced Installer 22.6/bin/x86/AdvancedInstaller.com"

DESKTOP_BUILD_PATH="$PROJECT_DIR/desktopApp/build/compose/binaries/main-release/msi"
MSI_FILE=$(find "$DESKTOP_BUILD_PATH" -name "Neuro*.msi" | head -n 1)
[ -z "$MSI_FILE" ] && { echo "[ERROR] MSI file not found"; post_error_message "$BRANCH_NAME"; exit 1; }

NEW_MSI_PATH="$DESKTOP_BUILD_PATH/Neuro_Desktop-${VERSION_NAME}-${VERSION_CODE}.msi"
[ -f "$NEW_MSI_PATH" ] && rm -f "$NEW_MSI_PATH"
mv "$MSI_FILE" "$NEW_MSI_PATH" || { echo "[ERROR] Failed to rename MSI"; exit 1; }

/c/ProgramData/chocolatey/bin/lessmsi.exe x "$NEW_MSI_PATH" || { echo "[ERROR] Failed to extract MSI"; exit 1; }

sleep 10

EXTRACT_DIR="/c/Users/BlackBricks/StudioProjects/SA_Neuro_Multiplatform/Neuro_Desktop-${VERSION_NAME}-${VERSION_CODE}/SourceDir/Neuro Desktop"

rm -rf "${ADVANCED_INSTALLER_SETUP_FILES}/app"
rm -rf "${ADVANCED_INSTALLER_SETUP_FILES}/runtime"

cp -r "${EXTRACT_DIR}/app" "${ADVANCED_INSTALLER_SETUP_FILES}/" || { echo "[ERROR] Failed to copy app"; exit 1; }
cp -r "${EXTRACT_DIR}/runtime" "${ADVANCED_INSTALLER_SETUP_FILES}/" || { echo "[ERROR] Failed to copy runtime"; exit 1; }

# === Step 3: Clean old entries ===
echo "[INFO] Cleaning .aip from old app/runtime references..."
sed -i '/SourcePath=".*app\//d' "$ADVANCED_INSTALLER_CONFIG"
sed -i '/SourcePath=".*runtime\//d' "$ADVANCED_INSTALLER_CONFIG"
sed -i '/DefaultDir="app"/d' "$ADVANCED_INSTALLER_CONFIG"
sed -i '/DefaultDir="runtime"/d' "$ADVANCED_INSTALLER_CONFIG"

# === Step 4: Update ProductVersion ===
echo "[INFO] Updating ProductVersion to $VERSION_NAME..."
sed -i "s/\(Property=\"ProductVersion\" Value=\"\)[^\"]*\(\".*\)/\1${VERSION_NAME}\2/" "$ADVANCED_INSTALLER_CONFIG"

# === Step 5: Update ProductCode ===
echo "[INFO] Generating new ProductCode..."
NEW_GUID=$(powershell.exe "[guid]::NewGuid().ToString()" | tr -d '\r')
[ -z "$NEW_GUID" ] && { echo "[ERROR] Failed to generate ProductCode"; exit 1; }
sed -i "s/\(Property=\"ProductCode\" Value=\"\)[^\"]*\(\".*\)/\1${NEW_GUID}\2/" "$ADVANCED_INSTALLER_CONFIG"

# === Step 6: Update MSI output name ===
echo "[INFO] Updating PackageFileName..."
sed -i "s/\(PackageFileName=\"Neuro_Desktop-\)[^\"]*\(\".*\)/\1${VERSION_NAME}-${VERSION_CODE}\2/" "$ADVANCED_INSTALLER_CONFIG"

# === Шаг 7: Подготовка CLI import команд ===
echo "[INFO] Preparing CLI import commands for app/runtime..."

WIN_APP_PATH=$(cygpath -w "${ADVANCED_INSTALLER_SETUP_FILES}/app")
WIN_RUNTIME_PATH=$(cygpath -w "${ADVANCED_INSTALLER_SETUP_FILES}/runtime")

# === Шаг 8: Удаление старых app/runtime ===
echo "[INFO] Removing old app/runtime folders..."
cmd.exe /C "\"$ADVANCED_INSTALLER\" /edit \"$ADVANCED_INSTALLER_CONFIG\" /DelFolder -path APPDIR\\app" || {
  echo "[WARN] Could not delete APPDIR\\app — it may not exist yet."
}
cmd.exe /C "\"$ADVANCED_INSTALLER\" /edit \"$ADVANCED_INSTALLER_CONFIG\" /DelFolder -path APPDIR\\runtime" || {
  echo "[WARN] Could not delete APPDIR\\runtime — it may not exist yet."
}

# === Шаг 9: Импорт новых папок ===
echo "[INFO] Adding updated app/runtime folders..."
cmd.exe /C "\"$ADVANCED_INSTALLER\" /edit \"$ADVANCED_INSTALLER_CONFIG\" /AddFolder -path APPDIR -source \"$WIN_APP_PATH\"" || {
  echo "[ERROR] Failed to add app folder to AIP"
  exit 1
}
cmd.exe /C "\"$ADVANCED_INSTALLER\" /edit \"$ADVANCED_INSTALLER_CONFIG\" /AddFolder -path APPDIR -source \"$WIN_RUNTIME_PATH\"" || {
  echo "[ERROR] Failed to add runtime folder to AIP"
  exit 1
}

# === Шаг 10: Сборка ===
echo "[INFO] Building installer..."
cmd.exe /C "\"$ADVANCED_INSTALLER\" /build \"$ADVANCED_INSTALLER_CONFIG\"" || {
  echo "[ERROR] Build failed"
  exit 1
}

#SIGNED_MSI_PATH="$ADVANCED_INSTALLER_MSI_FILES/Neuro_Desktop-${VERSION_NAME}-${VERSION_CODE}.msi"
# signtool sign /fd sha256 /tr http://ts.ssl.com /td sha256 /sha1 20fbd34014857033bcc6dabfae390411b22b0b1e "$SIGNED_MSI_PATH"

#echo "Uploading signed MSI to Slack: $SIGNED_MSI_PATH"
#execute_file_upload "$SLACK_BOT_TOKEN" "$SLACK_CHANNEL" ":white_check_mark: Windows build for \`$BRANCH_NAME\`" "upload" "$SIGNED_MSI_PATH"
#delete_message "$SLACK_BOT_TOKEN" "$SLACK_CHANNEL" "$first_ts"
