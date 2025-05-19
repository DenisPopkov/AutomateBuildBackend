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
        echo "[ERROR] Errors found in $ERROR_LOG_FILE:"
        cat "$ERROR_LOG_FILE" | iconv -f CP1251 -t UTF-8
        exit 1
    fi
}

log() {
    echo "$1"
}

post_error_message() {
    local branch_name=$1
    if [ -z "$SLACK_BOT_TOKEN" ] || [ -z "$SLACK_CHANNEL" ]; then
        log "[WARNING] SLACK_BOT_TOKEN or SLACK_CHANNEL not set, skipping Slack upload"
        return 1
    fi
    local message=":x: Failed to build Windows on \`$branch_name\`"
    execute_file_upload "$SLACK_BOT_TOKEN" "$SLACK_CHANNEL" "$message" "upload" "$ERROR_LOG_FILE" || {
        log "[WARNING] Failed to upload error log to Slack"
        return 1
    }
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
log "[INFO] MSI_FILE: $MSI_FILE"
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
"$LESSMSI" x "$MSI_WIN_PATH" 2>> "$ERROR_LOG_FILE" || { log "[ERROR] Failed to extract MSI"; cat "$ERROR_LOG_FILE" | iconv -f CP1251 -t UTF-8; post_error_message "$BRANCH_NAME"; exit 1; }
check_error_log

if [ -d "$EXTRACT_DIR" ]; then
    log "[INFO] MSI extracted to: $EXTRACT_DIR"
else
    log "[ERROR] Extracted directory not found: $EXTRACT_DIR"
    post_error_message "$BRANCH_NAME"
    exit 1
fi

log "[INFO] Updating .aip with new .jar files..."
if [ ! -d "$EXTRACT_DIR/app" ]; then
    log "[ERROR] Directory $EXTRACT_DIR/app does not exist"
    post_error_message "$BRANCH_NAME"
    exit 1
fi

log "[INFO] Removing old files from ADV_INST_SETUP_FILES..."
[ -d "${ADV_INST_SETUP_FILES}/app" ] && rm -rf "${ADV_INST_SETUP_FILES}/app" && log "[INFO] Old app folder removed" || log "[INFO] No old app folder to remove"
[ -f "${ADV_INST_SETUP_FILES}/Neuro Desktop.exe" ] && rm -f "${ADV_INST_SETUP_FILES}/Neuro Desktop.exe" && log "[INFO] Old Neuro Desktop.exe removed" || log "[INFO] No old Neuro Desktop.exe to remove"

# New logic to clean .jar references
log "[INFO] Cleaning old .jar file references in $ADV_INST_CONFIG..."
cp "$ADV_INST_CONFIG" "${ADV_INST_CONFIG}.backup" || {
    log "[ERROR] Failed to backup $ADV_INST_CONFIG";
    post_error_message "$BRANCH_NAME";
    exit 1;
}
sed -i '/<FILE.*app\\.*\.jar.*<\/FILE>/d' "$ADV_INST_CONFIG" || {
    log "[ERROR] Failed to remove old .jar references from $ADV_INST_CONFIG";
    post_error_message "$BRANCH_NAME";
    exit 1;
}
log "[INFO] Old .jar file references removed from $ADV_INST_CONFIG"

log "[INFO] Copying new app folder and Neuro Desktop.exe..."
cp -rf "${EXTRACT_DIR}/app" "${ADV_INST_SETUP_FILES}/app" || { log "[ERROR] Failed to copy app folder"; post_error_message "$BRANCH_NAME"; exit 1; }
[ -d "${ADV_INST_SETUP_FILES}/app" ] && log "[INFO] App folder copied successfully" || { log "[ERROR] App folder not found after copy"; post_error_message "$BRANCH_NAME"; exit 1; }

APP_JAR_DIR="${ADV_INST_SETUP_FILES}/app"
declare -a JAR_PATTERNS=("output-*.jar" "shared-jvm-*.jar" "skiko-awt-runtime-windows-x64-*.jar")

TEMP_AIP="${ADV_INST_CONFIG}.tmp"
cp "$ADV_INST_CONFIG" "$TEMP_AIP"

JAR_MAP_FILE=$(mktemp --suffix=.psd1)

echo "@{" > "$JAR_MAP_FILE"
for pattern in "${JAR_PATTERNS[@]}"; do
    jar_path=$(find "$APP_JAR_DIR" -name "$pattern" -print -quit)
    jar_name=$(basename "$jar_path")

    if [ -z "$jar_name" ]; then
        log "[WARNING] Jar not found for pattern: $pattern"
        continue
    fi

    log "[INFO] Found jar for pattern $pattern: $jar_name"
    echo "    \"$pattern\" = \"$jar_name\";" >> "$JAR_MAP_FILE"
done
echo "}" >> "$JAR_MAP_FILE"

if ! powershell -ExecutionPolicy Bypass -File "C:/Users/BlackBricks/PycharmProjects/AutomateBuildBackend/parser.ps1" \
  -AipFile "$TEMP_AIP" \
  -JarMapFile "$JAR_MAP_FILE"; then
    log "[ERROR] PowerShell script failed"
    post_error_message "$BRANCH_NAME"
    rm -f "$JAR_MAP_FILE" "$TEMP_AIP"
    exit 1
fi

mv "$TEMP_AIP" "$ADV_INST_CONFIG"
log "[SUCCESS] All .jar references updated successfully."

rm -f "$JAR_MAP_FILE"

cp -f "${EXTRACT_DIR}/Neuro Desktop.exe" "${ADV_INST_SETUP_FILES}/Neuro Desktop.exe" || {
    log "[ERROR] Failed to copy Neuro Desktop.exe"
    post_error_message "$BRANCH_NAME"
    exit 1
}

if [ -f "${ADV_INST_SETUP_FILES}/Neuro Desktop.exe" ]; then
    log "[INFO] Neuro Desktop.exe copied successfully"
else
    log "[ERROR] Neuro Desktop.exe not found after copy"
    post_error_message "$BRANCH_NAME"
    exit 1
fi

log "[INFO] Updating version, product code, and package file name in $ADV_INST_CONFIG..."
ADV_INST_WIN_PATH=$(convert_path "$ADV_INST_PATH")
CONFIG_WIN_PATH=$(convert_path "$ADV_INST_CONFIG")

log "[INFO] Setting ProductVersion to $VERSION_NAME..."
if cmd.exe /c "chcp 65001 > nul && \"${ADV_INST_WIN_PATH}\" /edit \"${CONFIG_WIN_PATH}\" /SetVersion ${VERSION_NAME}" 2>&1; then
    log "[INFO] ProductVersion updated to ${VERSION_NAME}"
else
    log "[ERROR] Failed to update ProductVersion"
    post_error_message "$BRANCH_NAME"
    exit 1
fi

log "[INFO] Updating version, product code, and package file name in $ADV_INST_CONFIG..."
ADV_INST_WIN_PATH=$(convert_path "$ADV_INST_PATH")
CONFIG_WIN_PATH=$(convert_path "$ADV_INST_CONFIG")

log "[INFO] Setting ProductVersion to $VERSION_NAME..."
cmd.exe /c "chcp 65001 > nul && \"${ADV_INST_WIN_PATH}\" /edit \"${CONFIG_WIN_PATH}\" /SetVersion ${VERSION_NAME}" 2>&1
if [ $? -eq 0 ]; then
    log "[INFO] ProductVersion updated to ${VERSION_NAME}"
else
    log "[ERROR] Failed to update ProductVersion"
    post_error_message "$BRANCH_NAME"
    exit 1
fi

log "[INFO] Generating new ProductCode GUID..."
NEW_GUID=$(powershell.exe -Command "[guid]::NewGuid().ToString()" | tr -d '\r\n ')
if [ -z "$NEW_GUID" ]; then
    log "[ERROR] Failed to generate ProductCode GUID"
    post_error_message "$BRANCH_NAME"
    exit 1
fi

log "[INFO] Setting ProductCode to {$NEW_GUID}..."
cmd.exe /c "chcp 65001 > nul && \"${ADV_INST_WIN_PATH}\" /edit \"${CONFIG_WIN_PATH}\" /SetProductCode -langid 1033 -guid {$NEW_GUID}" 2>&1
if [ $? -eq 0 ]; then
    log "[INFO] ProductCode updated to {$NEW_GUID}"
else
    log "[ERROR] Failed to update ProductCode"
    post_error_message "$BRANCH_NAME"
    exit 1
fi

log "[INFO] Setting PackageFileName to Neuro_Desktop-${VERSION_NAME}-${VERSION_CODE}..."
cmd.exe /c "chcp 65001 > nul && \"${ADV_INST_WIN_PATH}\" /edit \"${CONFIG_WIN_PATH}\" /SetProperty PackageFileName=Neuro_Desktop-${VERSION_NAME}-${VERSION_CODE}" 2>&1
if [ $? -eq 0 ]; then
    log "[INFO] PackageFileName updated"
else
    log "[ERROR] Failed to update PackageFileName"
    post_error_message "$BRANCH_NAME"
    exit 1
fi

log "[INFO] Building MSI with Advanced Installer..."
BUILD_OUTPUT=$(cmd.exe /c "chcp 65001 > nul && \"${ADV_INST_WIN_PATH}\" /build \"${CONFIG_WIN_PATH}\"" 2>&1)
if [ $? -eq 0 ]; then
    log "[INFO] MSI built successfully"
    log "[DEBUG] Contents of $ADVANCED_INSTALLER_MSI_FILES:"
    ls -la "$ADVANCED_INSTALLER_MSI_FILES"
else
    log "[ERROR] Failed to build MSI"
    log "$BUILD_OUTPUT"
    post_error_message "$BRANCH_NAME"
    exit 1
fi

sleep 20

log "[INFO] Renaming MSI file in ADVANCED_INSTALLER_MSI_FILES..."
ADVANCED_MSI_FILE=$(find "$ADVANCED_INSTALLER_MSI_FILES" -name "Neuro*.msi" -type f -printf "%T@ %p\n" | sort -nr | head -n 1 | cut -d' ' -f2-)
log "[DEBUG] ADVANCED_MSI_FILE is: $ADVANCED_MSI_FILE"

if [ -z "$ADVANCED_MSI_FILE" ]; then
    log "[ERROR] MSI file not found in $ADVANCED_INSTALLER_MSI_FILES"
    post_error_message "$BRANCH_NAME"
    exit 1
fi

if [ ! -f "$ADVANCED_MSI_FILE" ]; then
    log "[ERROR] MSI file does not exist at $ADVANCED_MSI_FILE"
    post_error_message "$BRANCH_NAME"
    exit 1
fi

if [ ! -r "$ADVANCED_MSI_FILE" ] || [ ! -w "$ADVANCED_MSI_FILE" ]; then
    log "[ERROR] Insufficient permissions for $ADVANCED_MSI_FILE"
    post_error_message "$BRANCH_NAME"
    exit 1
fi

# Wait to ensure the file is not locked
sleep 120

if lsof "$ADVANCED_MSI_FILE" >/dev/null 2>&1; then
    log "[ERROR] File $ADVANCED_MSI_FILE is in use"
    post_error_message "$BRANCH_NAME"
    exit 1
fi

NEW_ADVANCED_MSI_PATH="$ADVANCED_INSTALLER_MSI_FILES/Neuro_Desktop-${VERSION_NAME}-${VERSION_CODE}.msi"
log "[DEBUG] NEW_ADVANCED_MSI_PATH is: $NEW_ADVANCED_MSI_PATH"

if [ "$ADVANCED_MSI_FILE" = "$NEW_ADVANCED_MSI_PATH" ]; then
    log "[INFO] MSI file is already correctly named: $NEW_ADVANCED_MSI_PATH"
else
    if [ -f "$NEW_ADVANCED_MSI_PATH" ]; then
        rm -f "$NEW_ADVANCED_MSI_PATH" || {
            log "[ERROR] Failed to remove existing MSI at $NEW_ADVANCED_MSI_PATH"
            post_error_message "$BRANCH_NAME"
            exit 1
        }
    fi
    mv "$ADVANCED_MSI_FILE" "$NEW_ADVANCED_MSI_PATH" || {
        log "[ERROR] Failed to rename MSI in ADVANCED_INSTALLER_MSI_FILES"
        post_error_message "$BRANCH_NAME"
        exit 1
    }
    log "[INFO] Renamed MSI to: $NEW_ADVANCED_MSI_PATH"
fi

log "[INFO] Preparing to upload MSI to Slack..."
SIGNED_MSI_WIN_PATH=$(convert_path "$NEW_ADVANCED_MSI_PATH")
log "[INFO] Expected MSI path: $SIGNED_MSI_WIN_PATH"

if [ ! -f "$NEW_ADVANCED_MSI_PATH" ]; then
    log "[ERROR] MSI file not found at $NEW_ADVANCED_MSI_PATH"
    post_error_message "$BRANCH_NAME"
    exit 1
fi

log "[INFO] Cleaning up temporary files..."
rm -rf "$EXTRACT_DIR" && log "[INFO] Temporary extract directory removed" || log "[WARNING] Failed to remove temporary extract directory"

log "[INFO] Signing MSI: $SIGNED_MSI_WIN_PATH"
SIGNTOOL_PATH="C:\\Program Files (x86)\\Windows Kits\\10\\bin\\10.0.20348.0\\x86\\signtool.exe"
cmd.exe /C "\"\"$SIGNTOOL_PATH\" sign /fd sha256 /tr http://ts.ssl.com /td sha256 /sha1 20fbd34014857033bcc6dabfae390411b22b0b1e \"$SIGNED_MSI_WIN_PATH\"\"" || {
    log "[ERROR] Failed to sign MSI"
    post_error_message "$BRANCH_NAME"
    exit 1
}

log "[INFO] Uploading MSI to Slack: $SIGNED_MSI_WIN_PATH"
execute_file_upload "$SLACK_BOT_TOKEN" "$SLACK_CHANNEL" ":white_check_mark: Windows build for \`$BRANCH_NAME\`" "upload" "$SIGNED_MSI_WIN_PATH" || {
    log "[WARNING] Failed to upload MSI to Slack"
}
delete_message "$SLACK_BOT_TOKEN" "$SLACK_CHANNEL" "$first_ts" || {
    log "[WARNING] Failed to delete Slack message"
}
