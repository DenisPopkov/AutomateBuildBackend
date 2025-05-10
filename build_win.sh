#!/bin/bash

export LC_ALL=C.UTF-8
export LANG=C.UTF-8

source "./slack_upload.sh"
source "./utils.sh"

BRANCH_NAME=$1
isUseDevAnalytics=$2

SECRET_FILE="/c/Users/BlackBricks/Desktop/secret.txt"
ERROR_LOG_FILE="/tmp/build_error_log.txt"
PROJECT_DIR="/c/Users/BlackBricks/StudioProjects/SA_Neuro_Multiplatform"
ADV_INST_CONFIG="/c/Users/BlackBricks/Applications/Neuro installer/installer_win/Neuro Desktop 2.aip"
ADV_INST_SETUP_FILES="/c/Users/BlackBricks/Applications/Neuro installer"
ADVANCED_INSTALLER_MSI_FILES="/c/Users/BlackBricks/Applications/Neuro installer/installer_win/Neuro Desktop-SetupFiles"
LESSMSI="/c/ProgramData/chocolatey/bin/lessmsi.exe"
ADV_INST_PATH="C:/Program Files (x86)/Caphyon/Advanced Installer 22.6/bin/x86/AdvancedInstaller.com"
LOG_FILE="/c/Users/BlackBricks/AppData/Local/Temp/build_win_log.txt"

convert_path() {
    local path="$1"
    if command -v cygpath >/dev/null; then
        cygpath -w "$path" | sed 's|\\|\\\\|g'
    else
        echo "$path" | sed 's|^/c/|C:\\\\|; s|/|\\\\|g'
    fi
}

check_error_log() {
    if [ -s "$ERROR_LOG_FILE" ]; then
        log "[ERROR] Errors found in $ERROR_LOG_FILE:"
        cat "$ERROR_LOG_FILE" | iconv -f CP1251 -t UTF-8 | tee -a "$LOG_FILE"
        exit 1
    fi
}

log() {
    echo "$1" | tee -a "$LOG_FILE"
}

check_aip_duplicates() {
    local aip_file="$1"
    local dir_name="runtime_Dir"
    local count
    count=$(grep -c "<ROW Directory=\"${dir_name}\"" "$aip_file")
    if [ "$count" -gt 1 ]; then
        log "[ERROR] Found $count definitions of $dir_name in $aip_file. Please remove duplicates manually."
        exit 1
    fi
}

post_error_message() {
    local branch_name=$1
    local message=":x: Failed to build Windows on \`$branch_name\`"
    execute_file_upload "$SLACK_BOT_TOKEN" "$SLACK_CHANNEL" "$message" "upload" "$ERROR_LOG_FILE"
}

[ -f "$ERROR_LOG_FILE" ] && rm -f "$ERROR_LOG_FILE"

if [ -z "$BRANCH_NAME" ]; then
    log "[ERROR] Branch name not provided"
    exit 1
fi

while IFS='=' read -r key value; do
    key=$(echo "$key" | xargs)
    value=$(echo "$value" | xargs)
    case "$key" in
        "SLACK_BOT_TOKEN") SLACK_BOT_TOKEN="$value" ;;
        "SLACK_CHANNEL") SLACK_CHANNEL="$value" ;;
    esac
done < "$SECRET_FILE"

cd "$PROJECT_DIR" || { log "[ERROR] Failed to change directory to $PROJECT_DIR"; exit 1; }

log "[INFO] Starting Git operations..."
git stash push -m "Pre-build stash" || { log "[ERROR] Failed to stash changes"; post_error_message "$BRANCH_NAME"; exit 1; }
git fetch --all || { log "[ERROR] Failed to fetch Git data"; post_error_message "$BRANCH_NAME"; exit 1; }
git checkout "$BRANCH_NAME" || { log "[ERROR] Failed to checkout branch $BRANCH_NAME"; post_error_message "$BRANCH_NAME"; exit 1; }
git pull origin "$BRANCH_NAME" --no-rebase || { log "[ERROR] Failed to pull branch $BRANCH_NAME"; post_error_message "$BRANCH_NAME"; exit 1; }

VERSION_CODE=$(grep '^desktop\.build\.number\s*=' gradle.properties | sed 's/.*=\s*\([0-9]*\)/\1/' | xargs)
VERSION_NAME=$(grep '^desktop\.version\s*=' gradle.properties | sed 's/.*=\s*\([0-9]*\.[0-9]*\.[0-9]*\)/\1/' | xargs)
if [ -z "$VERSION_CODE" ] || [ -z "$VERSION_NAME" ]; then
    log "[ERROR] Failed to parse version from gradle.properties"
    post_error_message "$BRANCH_NAME"
    exit 1
fi
log "[INFO] Version: $VERSION_NAME, Build: $VERSION_CODE"

log "[INFO] Bumping version..."
VERSION_CODE=$((VERSION_CODE + 1))
sed -i "s/^desktop\.build\.number\s*=\s*[0-9]*$/desktop.build.number=$VERSION_CODE/" gradle.properties || { log "[ERROR] Failed to update desktop.build.number"; post_error_message "$BRANCH_NAME"; exit 1; }
git add gradle.properties || { log "[ERROR] Failed to stage gradle.properties"; post_error_message "$BRANCH_NAME"; exit 1; }
git commit -m "Windows version bump to $VERSION_CODE" || { log "[ERROR] Failed to commit version bump"; post_error_message "$BRANCH_NAME"; exit 1; }
git push origin "$BRANCH_NAME" || { log "[ERROR] Failed to push version bump"; post_error_message "$BRANCH_NAME"; exit 1; }
log "[INFO] Version bumped to $VERSION_CODE and pushed"

log "[INFO] Removing old extract directory..."
EXTRACT_DIR="/c/Users/BlackBricks/StudioProjects/SA_Neuro_Multiplatform/Neuro_Desktop-${VERSION_NAME}-${VERSION_CODE}/SourceDir/Neuro Desktop"
[ -d "$EXTRACT_DIR" ] && rm -rf "$EXTRACT_DIR" && log "[INFO] Old extract directory removed" || log "[INFO] Extract directory does not exist"

analyticsMessage="prod"
[ "$isUseDevAnalytics" == "true" ] && analyticsMessage="dev"
log "[INFO] Analytics mode: $analyticsMessage"

end_time=$(date -d "+15 minutes" +"%H:%M")
message=":hammer_and_wrench: Windows build started on \`$BRANCH_NAME\` with $analyticsMessage analytics. It will be ready approximately at $end_time"
first_ts=$(post_message "$SLACK_BOT_TOKEN" "$SLACK_CHANNEL" "$message")
log "[INFO] Slack message posted with timestamp: $first_ts"

if [ "$isUseDevAnalytics" == "false" ]; then
    log "[INFO] Enabling production keys..."
    enable_prod_keys || { log "[ERROR] Failed to enable production keys"; post_error_message "$BRANCH_NAME"; exit 1; }
    sleep 5
    powershell -command "Add-Type -AssemblyName System.Windows.Forms; [System.Windows.Forms.SendKeys]::SendWait('^(+o)')" || { log "[ERROR] Failed to send keys"; post_error_message "$BRANCH_NAME"; exit 1; }
    sleep-protector 50 || { log "[ERROR] Failed in sleep-protector"; post_error_message "$BRANCH_NAME"; exit 1; }
fi

log "[INFO] Running gradlew packageReleaseMsi..."
./gradlew packageReleaseMsi || { log "[ERROR] Failed to run gradlew packageReleaseMsi"; post_error_message "$BRANCH_NAME"; exit 1; }

DESKTOP_BUILD_PATH="$PROJECT_DIR/desktopApp/build/compose/binaries/main-release/msi"
MSI_FILE=$(find "$DESKTOP_BUILD_PATH" -name "Neuro*.msi" | head -n 1)
if [ -z "$MSI_FILE" ]; then
    log "[ERROR] MSI file not found in $DESKTOP_BUILD_PATH"
    post_error_message "$BRANCH_NAME"
    exit 1
fi
log "[INFO] Found MSI: $MSI_FILE"

NEW_MSI_PATH="$DESKTOP_BUILD_PATH/Neuro_Desktop-${VERSION_NAME}-${VERSION_CODE}.msi"
[ -f "$NEW_MSI_PATH" ] && rm -f "$NEW_MSI_PATH"
mv "$MSI_FILE" "$NEW_MSI_PATH" || { log "[ERROR] Failed to rename MSI"; post_error_message "$BRANCH_NAME"; exit 1; }
log "[INFO] Renamed MSI to: $NEW_MSI_PATH"

MSI_WIN_PATH=$(convert_path "$NEW_MSI_PATH")
log "[INFO] Extracting MSI: $MSI_WIN_PATH"
if [ ! -f "$LESSMSI" ]; then
    log "[ERROR] lessmsi.exe not found at $LESSMSI"
    post_error_message "$BRANCH_NAME"
    exit 1
fi
"$LESSMSI" x "$MSI_WIN_PATH" 2>> "$ERROR_LOG_FILE" || { log "[ERROR] Failed to extract MSI"; cat "$ERROR_LOG_FILE" | iconv -f CP1251 -t UTF-8 | tee -a "$LOG_FILE"; post_error_message "$BRANCH_NAME"; exit 1; }
check_error_log

if [ -d "$EXTRACT_DIR" ]; then
    log "[INFO] MSI extracted to: $EXTRACT_DIR"
else
    log "[ERROR] Extracted directory not found: $EXTRACT_DIR"
    post_error_message "$BRANCH_NAME"
    exit 1
fi

log "[INFO] Removing old app and runtime folders..."
[ -d "${ADV_INST_SETUP_FILES}/app" ] && rm -rf "${ADV_INST_SETUP_FILES}/app" && log "[INFO] App folder removed" || log "[INFO] App folder does not exist"
[ -d "${ADV_INST_SETUP_FILES}/runtime" ] && rm -rf "${ADV_INST_SETUP_FILES}/runtime" && log "[INFO] Runtime folder removed" || log "[INFO] Runtime folder does not exist"

log "[INFO] Copying new app and runtime folders..."
cp -rf "${EXTRACT_DIR}/app" "${ADV_INST_SETUP_FILES}/app" || { log "[ERROR] Failed to copy app folder"; post_error_message "$BRANCH_NAME"; exit 1; }
[ -d "${ADV_INST_SETUP_FILES}/app" ] && log "[INFO] App folder copied" || { log "[ERROR] App folder not found after copy"; post_error_message "$BRANCH_NAME"; exit 1; }

cp -rf "${EXTRACT_DIR}/runtime" "${ADV_INST_SETUP_FILES}/runtime" || { log "[ERROR] Failed to copy runtime folder"; post_error_message "$BRANCH_NAME"; exit 1; }
[ -d "${ADV_INST_SETUP_FILES}/runtime" ] && log "[INFO] Runtime folder copied" || { log "[ERROR] Runtime folder not found after copy"; post_error_message "$BRANCH_NAME"; exit 1; }

log "[INFO] Checking $ADV_INST_CONFIG for duplicates..."
check_aip_duplicates "$ADV_INST_CONFIG"

log "[INFO] Updating version and product code in $ADV_INST_CONFIG..."
sed -i "s/\(Property=\"ProductVersion\" Value=\"\)[^\"]*\(\".*\)/\1${VERSION_NAME}\2/" "$ADV_INST_CONFIG" || { log "[ERROR] Failed to update ProductVersion"; post_error_message "$BRANCH_NAME"; exit 1; }
NEW_GUID=$(powershell.exe "[guid]::NewGuid().ToString()" | tr -d '\r')
[ -n "$NEW_GUID" ] || { log "[ERROR] Failed to generate ProductCode"; post_error_message "$BRANCH_NAME"; exit 1; }
sed -i "s/\(Property=\"ProductCode\" Value=\"\)[^\"]*\(\".*\)/\1${NEW_GUID}\2/" "$ADV_INST_CONFIG" || { log "[ERROR] Failed to update ProductCode"; post_error_message "$BRANCH_NAME"; exit 1; }
sed -i "s/\(PackageFileName=\"Neuro_Desktop-\)[^\"]*\(\".*\)/\1${VERSION_NAME}-${VERSION_CODE}\2/" "$ADV_INST_CONFIG" || { log "[ERROR] Failed to update PackageFileName"; post_error_message "$BRANCH_NAME"; exit 1; }

log "[INFO] Building MSI with Advanced Installer..."
ADV_INST_WIN_PATH=$(convert_path "$ADV_INST_PATH")
CONFIG_WIN_PATH=$(convert_path "$ADV_INST_CONFIG")
cmd.exe /c "chcp 65001 > nul && \"${ADV_INST_WIN_PATH}\" /build \"${CONFIG_WIN_PATH}\"" 2>> "$ERROR_LOG_FILE" || { log "[ERROR] Failed to build MSI"; cat "$ERROR_LOG_FILE" | iconv -f CP1251 -t UTF-8 | tee -a "$LOG_FILE"; post_error_message "$BRANCH_NAME"; exit 1; }
check_error_log

log "[INFO] Build completed successfully."

SIGNED_MSI_PATH="$ADVANCED_INSTALLER_MSI_FILES/Neuro_Desktop-${VERSION_NAME}-${VERSION_CODE}.msi"
#signtool sign /fd sha256 /tr http://ts.ssl.com /td sha256 /sha1 20fbd34014857033bcc6dabfae390411b22b0b1e "$SIGNED_MSI_PATH"

execute_file_upload "$SLACK_BOT_TOKEN" "$SLACK_CHANNEL" ":white_check_mark: Windows build for \`$BRANCH_NAME\`" "upload" "$SIGNED_MSI_PATH"
delete_message "$SLACK_BOT_TOKEN" "$SLACK_CHANNEL" "$first_ts"
