#!/bin/bash

export LC_ALL=C.UTF-8
export LANG=C.UTF-8

source "./slack_upload.sh"
source "./utils.sh"

ERROR_LOG_FILE="/tmp/build_error_log.txt"
PROJECT_DIR="/c/Users/BlackBricks/StudioProjects/SA_Neuro_Multiplatform"
ADV_INST_CONFIG="/c/Users/BlackBricks/Applications/Neuro installer/installer_win/Neuro Desktop 2.aip"
ADV_INST_SETUP_FILES="/c/Users/BlackBricks/Applications/Neuro installer"
LESSMSI="/c/ProgramData/chocolatey/bin/lessmsi.exe"
ADV_INST_PATH="C:/Program Files (x86)/Caphyon/Advanced Installer 22.6/bin/x86/AdvancedInstaller.com"
XMLSTARLET="/c/ProgramData/chocolatey/bin/xmlstarlet.exe"
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

[ -f "$ERROR_LOG_FILE" ] && rm -f "$ERROR_LOG_FILE"

cd "$PROJECT_DIR" || { log "[ERROR] Failed to change directory to $PROJECT_DIR"; exit 1; }

VERSION_CODE=$(grep '^desktop\.build\.number\s*=' gradle.properties | sed 's/.*=\s*\([0-9]*\)/\1/' | xargs)
VERSION_NAME=$(grep '^desktop\.version\s*=' gradle.properties | sed 's/.*=\s*\([0-9]*\.[0-9]*\.[0-9]*\)/\1/' | xargs)
if [ -z "$VERSION_CODE" ] || [ -z "$VERSION_NAME" ]; then
    log "[ERROR] Failed to parse version from gradle.properties"
    exit 1
fi
log "[INFO] Version: $VERSION_NAME, Build: $VERSION_CODE"

DESKTOP_BUILD_PATH="$PROJECT_DIR/desktopApp/build/compose/binaries/main-release/msi"
MSI_FILE=$(find "$DESKTOP_BUILD_PATH" -name "Neuro*.msi" | head -n 1)
if [ -z "$MSI_FILE" ]; then
    log "[ERROR] MSI file not found in $DESKTOP_BUILD_PATH"
    exit 1
fi
log "[INFO] Found MSI: $MSI_FILE"

NEW_MSI_PATH="$DESKTOP_BUILD_PATH/Neuro_Desktop-${VERSION_NAME}-${VERSION_CODE}.msi"
[ -f "$NEW_MSI_PATH" ] && rm -f "$NEW_MSI_PATH"
mv "$MSI_FILE" "$NEW_MSI_PATH" || { log "[ERROR] Failed to rename MSI"; exit 1; }
log "[INFO] Renamed MSI to: $NEW_MSI_PATH"

MSI_WIN_PATH=$(convert_path "$NEW_MSI_PATH")
log "[INFO] Extracting MSI: $MSI_WIN_PATH"
"$LESSMSI" x "$MSI_WIN_PATH" 2>> "$ERROR_LOG_FILE" || { log "[ERROR] Failed to extract MSI"; cat "$ERROR_LOG_FILE" | iconv -f CP1251 -t UTF-8 | tee -a "$LOG_FILE"; exit 1; }
check_error_log

EXTRACT_DIR="/c/Users/BlackBricks/StudioProjects/SA_Neuro_Multiplatform/Neuro_Desktop-${VERSION_NAME}-${VERSION_CODE}/SourceDir/Neuro Desktop"
if [ -d "$EXTRACT_DIR" ]; then
    log "[INFO] MSI extracted to: $EXTRACT_DIR"
else
    log "[ERROR] Extracted directory not found: $EXTRACT_DIR"
    exit 1
fi

log "[INFO] Removing old app and runtime folders..."
[ -d "${ADV_INST_SETUP_FILES}/app" ] && rm -rf "${ADV_INST_SETUP_FILES}/app" && log "[INFO] App folder removed" || log "[INFO] App folder does not exist"
[ -d "${ADV_INST_SETUP_FILES}/runtime" ] && rm -rf "${ADV_INST_SETUP_FILES}/runtime" && log "[INFO] Runtime folder removed" || log "[INFO] Runtime folder does not exist"

log "[INFO] Copying new app and runtime folders..."
cp -rf "${EXTRACT_DIR}/app" "${ADV_INST_SETUP_FILES}/app" || { log "[ERROR] Failed to copy app folder"; exit 1; }
[ -d "${ADV_INST_SETUP_FILES}/app" ] && log "[INFO] App folder copied" || { log "[ERROR] App folder not found after copy"; exit 1; }

cp -rf "${EXTRACT_DIR}/runtime" "${ADV_INST_SETUP_FILES}/runtime" || { log "[ERROR] Failed to copy runtime folder"; exit 1; }
[ -d "${ADV_INST_SETUP_FILES}/runtime" ] && log "[INFO] Runtime folder copied" || { log "[ERROR] Runtime folder not found after copy"; exit 1; }

log "[INFO] Checking $ADV_INST_CONFIG for duplicates..."
check_aip_duplicates "$ADV_INST_CONFIG"

log "[INFO] Updating version and product code in $ADV_INST_CONFIG..."
"$XMLSTARLET" ed -L -u "//ROW[@Property='ProductVersion']/@Value" -v "${VERSION_NAME}" "$ADV_INST_CONFIG" || { log "[ERROR] Failed to update ProductVersion"; exit 1; }
NEW_GUID=$(powershell.exe "[guid]::NewGuid().ToString()" | tr -d '\r')
[ -n "$NEW_GUID" ] || { log "[ERROR] Failed to generate ProductCode"; exit 1; }
"$XMLSTARLET" ed -L -u "//ROW[@Property='ProductCode']/@Value" -v "${NEW_GUID}" "$ADV_INST_CONFIG" || { log "[ERROR] Failed to update ProductCode"; exit 1; }
"$XMLSTARLET" ed -L -u "//ROW[@Property='PackageFileName']/@Value" -v "Neuro_Desktop-${VERSION_NAME}-${VERSION_CODE}" "$ADV_INST_CONFIG" || { log "[ERROR] Failed to update PackageFileName"; exit 1; }

log "[INFO] Building MSI with Advanced Installer..."
cmd.exe /c "chcp 65001 > nul && \"$ADV_INST_PATH\" /build \"$(convert_path "$ADV_INST_CONFIG")\"" 2>> "$ERROR_LOG_FILE" || { log "[ERROR] Failed to build MSI"; cat "$ERROR_LOG_FILE" | iconv -f CP1251 -t UTF-8 | tee -a "$LOG_FILE"; exit 1; }
check_error_log

log "[INFO] Build completed successfully."