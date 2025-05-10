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

convert_path() {
    local path="$1"
    if command -v cygpath >/dev/null; then
        cygpath -w "$path" | sed 's|\\|\\\\|g'
    else
        echo "$path" | sed 's|^/c/|C:\\\\|; s|/|\\\\|g'
    fi
}

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
[ -z "$MSI_FILE" ] && { echo "[ERROR] MSI file not found"; exit 1; }

NEW_MSI_PATH="$DESKTOP_BUILD_PATH/Neuro_Desktop-${VERSION_NAME}-${VERSION_CODE}.msi"
[ -f "$NEW_MSI_PATH" ] && rm -f "$NEW_MSI_PATH"
mv "$MSI_FILE" "$NEW_MSI_PATH" || { echo "[ERROR] Failed to rename MSI"; exit 1; }

echo "[INFO] Extracting MSI..."
/c/ProgramData/chocolatey/bin/lessmsi.exe x "$NEW_MSI_PATH" || { echo "[ERROR] Failed to extract MSI"; exit 1; }

EXTRACT_DIR="/c/Users/BlackBricks/StudioProjects/SA_Neuro_Multiplatform/Neuro_Desktop-${VERSION_NAME}-${VERSION_CODE}/SourceDir/Neuro Desktop"

echo "[INFO] Removing old app and runtime folders..."
rm -rf "${ADV_INST_SETUP_FILES}/app"
rm -rf "${ADV_INST_SETUP_FILES}/runtime"

echo "[INFO] Copying new app and runtime folders..."
cp -r "${EXTRACT_DIR}/app" "${ADV_INST_SETUP_FILES}/" || { echo "[ERROR] Failed to copy 'app' folder"; exit 1; }
cp -r "${EXTRACT_DIR}/runtime" "${ADV_INST_SETUP_FILES}/" || { echo "[ERROR] Failed to copy 'runtime' folder"; exit 1; }

echo "[INFO] Backing up original .aip..."
cp "$ADV_INST_CONFIG" "${ADV_INST_CONFIG}.orig" || { echo "[ERROR] Failed to backup original .aip"; exit 1; }
cp "$ADV_INST_CONFIG" "${ADV_INST_CONFIG}.bak" || { echo "[ERROR] Failed to backup .aip"; exit 1; }

echo "[INFO] Updating version and product code..."
sed -i "s/\(Property=\"ProductVersion\" Value=\"\)[^\"]*\(\".*\)/\1${VERSION_NAME}\2/" "$ADV_INST_CONFIG"
NEW_GUID=$(powershell.exe "[guid]::NewGuid().ToString()" | tr -d '\r')
[ -z "$NEW_GUID" ] && { echo "[ERROR] Failed to generate ProductCode"; exit 1; }
sed -i "s/\(Property=\"ProductCode\" Value=\"\)[^\"]*\(\".*\)/\1${NEW_GUID}\2/" "$ADV_INST_CONFIG"
sed -i "s/\(PackageFileName=\"Neuro_Desktop-\)[^\"]*\(\".*\)/\1${VERSION_NAME}-${VERSION_CODE}\2/" "$ADV_INST_CONFIG"

echo "[INFO] Checking for xmlstarlet..."
XMLSTARLET_PATH=$(command -v xmlstarlet || command -v xmlstarlet.exe || echo "C:/ProgramData/chocolatey/bin/xmlstarlet.exe")
if [ ! -x "$XMLSTARLET_PATH" ]; then
    echo "[ERROR] xmlstarlet is not installed or not executable."
    exit 1
fi
echo "[DEBUG] xmlstarlet found at: $XMLSTARLET_PATH" >> cleanup.log

sleep 10

echo "[INFO] Adding app and runtime directories to .aip..."
# Check if app_Dir or runtime_Dir already exist to avoid duplicates
if "$XMLSTARLET_PATH" sel -t -v "//COMPONENT[@cid='caphyon.advinst.msicomp.MsiDirsComponent']/TABLE[@Name='Directory']/ROW[@Directory='app_Dir']" "$ADV_INST_CONFIG" | grep -q .; then
    echo "[WARNING] app_Dir already exists in .aip, skipping addition"
else
    "$XMLSTARLET_PATH" ed --inplace \
        -s "//COMPONENT[@cid='caphyon.advinst.msicomp.MsiDirsComponent']/TABLE[@Name='Directory']" -t elem -n ROW \
        -s "//COMPONENT[@cid='caphyon.advinst.msicomp.MsiDirsComponent']/TABLE[@Name='Directory']/ROW[last()]" -t attr -n Directory -v "app_Dir" \
        -s "//COMPONENT[@cid='caphyon.advinst.msicomp.MsiDirsComponent']/TABLE[@Name='Directory']/ROW[last()]" -t attr -n Directory_Parent -v "NewFolder_Dir" \
        -s "//COMPONENT[@cid='caphyon.advinst.msicomp.MsiDirsComponent']/TABLE[@Name='Directory']/ROW[last()]" -t attr -n DefaultDir -v "app" \
        "$ADV_INST_CONFIG" 2>> "$ERROR_LOG_FILE" || { echo "[ERROR] Failed to add app_Dir"; exit 1; }
fi

if "$XMLSTARLET_PATH" sel -t -v "//COMPONENT[@cid='caphyon.advinst.msicomp.MsiDirsComponent']/TABLE[@Name='Directory']/ROW[@Directory='runtime_Dir']" "$ADV_INST_CONFIG" | grep -q .; then
    echo "[WARNING] runtime_Dir already exists in .aip, skipping addition"
else
    "$XMLSTARLET_PATH" ed --inplace \
        -s "//COMPONENT[@cid='caphyon.advinst.msicomp.MsiDirsComponent']/TABLE[@Name='Directory']" -t elem -n ROW \
        -s "//COMPONENT[@cid='caphyon.advinst.msicomp.MsiDirsComponent']/TABLE[@Name='Directory']/ROW[last()]" -t attr -n Directory -v "runtime_Dir" \
        -s "//COMPONENT[@cid='caphyon.advinst.msicomp.MsiDirsComponent']/TABLE[@Name='Directory']/ROW[last()]" -t attr -n Directory_Parent -v "NewFolder_Dir" \
        -s "//COMPONENT[@cid='caphyon.advinst.msicomp.MsiDirsComponent']/TABLE[@Name='Directory']/ROW[last()]" -t attr -n DefaultDir -v "runtime" \
        "$ADV_INST_CONFIG" 2>> "$ERROR_LOG_FILE" || { echo "[ERROR] Failed to add runtime_Dir"; exit 1; }
fi

# Add components for app and runtime directories
"$XMLSTARLET_PATH" ed --inplace \
    -s "//COMPONENT[@cid='caphyon.advinst.msicomp.MsiCompsComponent']/TABLE[@Name='Component']" -t elem -n ROW \
    -s "//COMPONENT[@cid='caphyon.advinst.msicomp.MsiCompsComponent']/TABLE[@Name='Component']/ROW[last()]" -t attr -n Component -v "app_Dir" \
    -s "//COMPONENT[@cid='caphyon.advinst.msicomp.MsiCompsComponent']/TABLE[@Name='Component']/ROW[last()]" -t attr -n ComponentId -v "{$(powershell.exe "[guid]::NewGuid().ToString()" | tr -d '\r')}" \
    -s "//COMPONENT[@cid='caphyon.advinst.msicomp.MsiCompsComponent']/TABLE[@Name='Component']/ROW[last()]" -t attr -n Directory_ -v "app_Dir" \
    -s "//COMPONENT[@cid='caphyon.advinst.msicomp.MsiCompsComponent']/TABLE[@Name='Component']/ROW[last()]" -t attr -n Attributes -v "0" \
    "$ADV_INST_CONFIG" 2>> "$ERROR_LOG_FILE" || { echo "[ERROR] Failed to add app_Dir component"; exit 1; }

"$XMLSTARLET_PATH" ed --inplace \
    -s "//COMPONENT[@cid='caphyon.advinst.msicomp.MsiCompsComponent']/TABLE[@Name='Component']" -t elem -n ROW \
    -s "//COMPONENT[@cid='caphyon.advinst.msicomp.MsiCompsComponent']/TABLE[@Name='Component']/ROW[last()]" -t attr -n Component -v "runtime_Dir" \
    -s "//COMPONENT[@cid='caphyon.advinst.msicomp.MsiCompsComponent']/TABLE[@Name='Component']/ROW[last()]" -t attr -n ComponentId -v "{$(powershell.exe "[guid]::NewGuid().ToString()" | tr -d '\r')}" \
    -s "//COMPONENT[@cid='caphyon.advinst.msicomp.MsiCompsComponent']/TABLE[@Name='Component']/ROW[last()]" -t attr -n Directory_ -v "runtime_Dir" \
    -s "//COMPONENT[@cid='caphyon.advinst.msicomp.MsiCompsComponent']/TABLE[@Name='Component']/ROW[last()]" -t attr -n Attributes -v "0" \
    "$ADV_INST_CONFIG" 2>> "$ERROR_LOG_FILE" || { echo "[ERROR] Failed to add runtime_Dir component"; exit 1; }

# Add app and runtime to feature components
"$XMLSTARLET_PATH" ed --inplace \
    -s "//COMPONENT[@cid='caphyon.advinst.msicomp.MsiFeatCompsComponent']/TABLE[@Name='FeatureComponents']" -t elem -n ROW \
    -s "//COMPONENT[@cid='caphyon.advinst.msicomp.MsiFeatCompsComponent']/TABLE[@Name='FeatureComponents']/ROW[last()]" -t attr -n Feature_ -v "MainFeature" \
    -s "//COMPONENT[@cid='caphyon.advinst.msicomp.MsiFeatCompsComponent']/TABLE[@Name='FeatureComponents']/ROW[last()]" -t attr -n Component_ -v "app_Dir" \
    "$ADV_INST_CONFIG" 2>> "$ERROR_LOG_FILE" || { echo "[ERROR] Failed to add app_Dir to features"; exit 1; }

"$XMLSTARLET_PATH" ed --inplace \
    -s "//COMPONENT[@cid='caphyon.advinst.msicomp.MsiFeatCompsComponent']/TABLE[@Name='FeatureComponents']" -t elem -n ROW \
    -s "//COMPONENT[@cid='caphyon.advinst.msicomp.MsiFeatCompsComponent']/TABLE[@Name='FeatureComponents']/ROW[last()]" -t attr -n Feature_ -v "MainFeature" \
    -s "//COMPONENT[@cid='caphyon.advinst.msicomp.MsiFeatCompsComponent']/TABLE[@Name='FeatureComponents']/ROW[last()]" -t attr -n Component_ -v "runtime_Dir" \
    "$ADV_INST_CONFIG" 2>> "$ERROR_LOG_FILE" || { echo "[ERROR] Failed to add runtime_Dir to features"; exit 1; }

# Add representative files for app and runtime
"$XMLSTARLET_PATH" ed --inplace \
    -s "//COMPONENT[@cid='caphyon.advinst.msicomp.MsiFilesComponent']/TABLE[@Name='File']" -t elem -n ROW \
    -s "//COMPONENT[@cid='caphyon.advinst.msicomp.MsiFilesComponent']/TABLE[@Name='File']/ROW[last()]" -t attr -n File -v "animationcoredesktop.jar" \
    -s "//COMPONENT[@cid='caphyon.advinst.msicomp.MsiFilesComponent']/TABLE[@Name='File']/ROW[last()]" -t attr -n Component_ -v "app_Dir" \
    -s "//COMPONENT[@cid='caphyon.advinst.msicomp.MsiFilesComponent']/TABLE[@Name='File']/ROW[last()]" -t attr -n FileName -v "ANIMAT~1.JAR|animation-core-desktop.jar" \
    -s "//COMPONENT[@cid='caphyon.advinst.msicomp.MsiFilesComponent']/TABLE[@Name='File']/ROW[last()]" -t attr -n Attributes -v "0" \
    -s "//COMPONENT[@cid='caphyon.advinst.msicomp.MsiFilesComponent']/TABLE[@Name='File']/ROW[last()]" -t attr -n SourcePath -v "..\app\animation-core-desktop.jar" \
    -s "//COMPONENT[@cid='caphyon.advinst.msicomp.MsiFilesComponent']/TABLE[@Name='File']/ROW[last()]" -t attr -n SelfReg -v "false" \
    "$ADV_INST_CONFIG" 2>> "$ERROR_LOG_FILE" || { echo "[ERROR] Failed to add app file"; exit 1; }

"$XMLSTARLET_PATH" ed --inplace \
    -s "//COMPONENT[@cid='caphyon.advinst.msicomp.MsiFilesComponent']/TABLE[@Name='File']" -t elem -n ROW \
    -s "//COMPONENT[@cid='caphyon.advinst.msicomp.MsiFilesComponent']/TABLE[@Name='File']/ROW[last()]" -t attr -n File -v "jvm.dll" \
    -s "//COMPONENT[@cid='caphyon.advinst.msicomp.MsiFilesComponent']/TABLE[@Name='File']/ROW[last()]" -t attr -n Component_ -v "runtime_Dir" \
    -s "//COMPONENT[@cid='caphyon.advinst.msicomp.MsiFilesComponent']/TABLE[@Name='File']/ROW[last()]" -t attr -n FileName -v "jvm.dll" \
    -s "//COMPONENT[@cid='caphyon.advinst.msicomp.MsiFilesComponent']/TABLE[@Name='File']/ROW[last()]" -t attr -n Attributes -v "256" \
    -s "//COMPONENT[@cid='caphyon.advinst.msicomp.MsiFilesComponent']/TABLE[@Name='File']/ROW[last()]" -t attr -n SourcePath -v "..\runtime\bin\server\jvm.dll" \
    -s "//COMPONENT[@cid='caphyon.advinst.msicomp.MsiFilesComponent']/TABLE[@Name='File']/ROW[last()]" -t attr -n SelfReg -v "false" \
    "$ADV_INST_CONFIG" 2>> "$ERROR_LOG_FILE" || { echo "[ERROR] Failed to add runtime file"; exit 1; }

echo "[INFO] Building MSI with Advanced Installer..."
ADV_INST_PATH="/c/Program Files (x86)/Caphyon/Advanced Installer 22.6/bin/x86/AdvancedInstaller.com"
"$ADV_INST_PATH" /build "$ADV_INST_CONFIG" || { echo "[ERROR] Failed to build MSI"; exit 1; }

echo "[INFO] Restoring original .aip to remove app and runtime references..."
mv "${ADV_INST_CONFIG}.orig" "$ADV_INST_CONFIG" || { echo "[ERROR] Failed to restore original .aip"; exit 1; }
rm -f "${ADV_INST_CONFIG}.bak"

echo "[INFO] Cleaning up temporary files..."
rm -rf "${ADV_INST_SETUP_FILES}/app"
rm -rf "${ADV_INST_SETUP_FILES}/runtime"

echo "[INFO] Build completed successfully."
#SIGNED_MSI_PATH="$ADVANCED_INSTALLER_MSI_FILES/Neuro_Desktop-${VERSION_NAME}-${VERSION_CODE}.msi"
# signtool sign /fd sha256 /tr http://ts.ssl.com /td sha256 /sha1 20fbd34014857033bcc6dabfae390411b22b0b1e "$SIGNED_MSI_PATH"

#echo "Uploading signed MSI to Slack: $SIGNED_MSI_PATH"
#execute_file_upload "$SLACK_BOT_TOKEN" "$SLACK_CHANNEL" ":white_check_mark: Windows build for \`$BRANCH_NAME\`" "upload" "$SIGNED_MSI_PATH"
#delete_message "$SLACK_BOT_TOKEN" "$SLACK_CHANNEL" "$first_ts"
