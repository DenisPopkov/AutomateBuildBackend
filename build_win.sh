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

# Функция для преобразования пути из /c/ в C:\ с экранированием
convert_path() {
    local path="$1"
    if command -v cygpath >/dev/null; then
        cygpath -w "$path" | sed 's|\\|\\\\|g'
    else
        echo "$path" | sed 's|^/c/|C:\\\\|; s|/|\\\\|g'
    fi
}

cd "$PROJECT_DIR" || exit 1

VERSION_CODE=$(grep '^desktop\.build\.number\s*=' gradle.properties | sed 's/.*=\s*\([0-9]*\)/\1/' | xargs)
VERSION_NAME=$(grep '^desktop\.version\s*=' gradle.properties | sed 's/.*=\s*\([0-9]*\.[0-9]*\.[0-9]*\)/\1/' | xargs)

DESKTOP_BUILD_PATH="$PROJECT_DIR/desktopApp/build/compose/binaries/main-release/msi"
MSI_FILE=$(find "$DESKTOP_BUILD_PATH" -name "Neuro*.msi" | head -n 1)
[ -z "$MSI_FILE" ] && { echo "[ERROR] MSI file not found"; exit 1; }

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
    echo "[ERROR] xmlstarlet is not installed or not executable."
    echo "[DEBUG] XMLSTARLET_PATH=$XMLSTARLET_PATH" >> cleanup.log
    exit 1
fi
echo "[DEBUG] xmlstarlet found at: $XMLSTARLET_PATH" >> cleanup.log

echo "[DEBUG] Saving pre-cleanup .aip copy..." >> cleanup.log
cp "$ADV_INST_CONFIG" "${ADV_INST_CONFIG}.preclean" || { echo "[ERROR] Failed to save pre-cleanup .aip copy"; exit 1; }

echo "[DEBUG] Removing app and runtime directories..." >> cleanup.log
"$XMLSTARLET_PATH" ed -d '//ROW[contains(@Directory, "app_Dir")]' "$ADV_INST_CONFIG" > "${ADV_INST_CONFIG}.tmp" && mv "${ADV_INST_CONFIG}.tmp" "$ADV_INST_CONFIG" || { echo "[ERROR] Failed to remove app directories"; exit 1; }
"$XMLSTARLET_PATH" ed -d '//ROW[contains(@Directory, "runtime_Dir")]' "$ADV_INST_CONFIG" > "${ADV_INST_CONFIG}.tmp" && mv "${ADV_INST_CONFIG}.tmp" "$ADV_INST_CONFIG" || { echo "[ERROR] Failed to remove runtime directories"; exit 1; }
"$XMLSTARLET_PATH" ed -d '//ROW[contains(@Directory_Parent, "app_Dir")]' "$ADV_INST_CONFIG" > "${ADV_INST_CONFIG}.tmp" && mv "${ADV_INST_CONFIG}.tmp" "$ADV_INST_CONFIG" || { echo "[ERROR] Failed to remove app parent directories"; exit 1; }
"$XMLSTARLET_PATH" ed -d '//ROW[contains(@Directory_Parent, "runtime_Dir")]' "$ADV_INST_CONFIG" > "${ADV_INST_CONFIG}.tmp" && mv "${ADV_INST_CONFIG}.tmp" "$ADV_INST_CONFIG" || { echo "[ERROR] Failed to remove runtime parent directories"; exit 1; }
"$XMLSTARLET_PATH" ed -d '//ROW[contains(@Directory_, "app_Dir")]' "$ADV_INST_CONFIG" > "${ADV_INST_CONFIG}.tmp" && mv "${ADV_INST_CONFIG}.tmp" "$ADV_INST_CONFIG" || { echo "[ERROR] Failed to remove app directory references"; exit 1; }
"$XMLSTARLET_PATH" ed -d '//ROW[contains(@Directory_, "runtime_Dir")]' "$ADV_INST_CONFIG" > "${ADV_INST_CONFIG}.tmp" && mv "${ADV_INST_CONFIG}.tmp" "$ADV_INST_CONFIG" || { echo "[ERROR] Failed to remove runtime directory references"; exit 1; }

echo "[DEBUG] Removing app and runtime components..." >> cleanup.log
"$XMLSTARLET_PATH" ed -d '//ROW[contains(@Component, "app")]' "$ADV_INST_CONFIG" > "${ADV_INST_CONFIG}.tmp" && mv "${ADV_INST_CONFIG}.tmp" "$ADV_INST_CONFIG" || { echo "[ERROR] Failed to remove app components"; exit 1; }
"$XMLSTARLET_PATH" ed -d '//ROW[contains(@Component, "runtime")]' "$ADV_INST_CONFIG" > "${ADV_INST_CONFIG}.tmp" && mv "${ADV_INST_CONFIG}.tmp" "$ADV_INST_CONFIG" || { echo "[ERROR] Failed to remove runtime components"; exit 1; }
"$XMLSTARLET_PATH" ed -d '//ROW[contains(@Component_, "app")]' "$ADV_INST_CONFIG" > "${ADV_INST_CONFIG}.tmp" && mv "${ADV_INST_CONFIG}.tmp" "$ADV_INST_CONFIG" || { echo "[ERROR] Failed to remove app component references"; exit 1; }
"$XMLSTARLET_PATH" ed -d '//ROW[contains(@Component_, "runtime")]' "$ADV_INST_CONFIG" > "${ADV_INST_CONFIG}.tmp" && mv "${ADV_INST_CONFIG}.tmp" "$ADV_INST_CONFIG" || { echo "[ERROR] Failed to remove runtime component references"; exit 1; }

echo "[DEBUG] Removing app and runtime files..." >> cleanup.log
"$XMLSTARLET_PATH" ed -d '//ROW[contains(@File, "app")]' "$ADV_INST_CONFIG" > "${ADV_INST_CONFIG}.tmp" && mv "${ADV_INST_CONFIG}.tmp" "$ADV_INST_CONFIG" || { echo "[ERROR] Failed to remove app files"; exit 1; }
"$XMLSTARLET_PATH" ed -d '//ROW[contains(@File, "runtime")]' "$ADV_INST_CONFIG" > "${ADV_INST_CONFIG}.tmp" && mv "${ADV_INST_CONFIG}.tmp" "$ADV_INST_CONFIG" || { echo "[ERROR] Failed to remove runtime files"; exit 1; }
"$XMLSTARLET_PATH" ed -d '//ROW[contains(@SourcePath, "app")]' "$ADV_INST_CONFIG" > "${ADV_INST_CONFIG}.tmp" && mv "${ADV_INST_CONFIG}.tmp" "$ADV_INST_CONFIG" || { echo "[ERROR] Failed to remove app SourcePath"; exit 1; }
"$XMLSTARLET_PATH" ed -d '//ROW[contains(@SourcePath, "runtime")]' "$ADV_INST_CONFIG" > "${ADV_INST_CONFIG}.tmp" && mv "${ADV_INST_CONFIG}.tmp" "$ADV_INST_CONFIG" || { echo "[ERROR] Failed to remove runtime SourcePath"; exit 1; }

echo "[DEBUG] Saving post-cleanup .aip copy..." >> cleanup.log
cp "$ADV_INST_CONFIG" "${ADV_INST_CONFIG}.postclean" || { echo "[ERROR] Failed to save post-cleanup .aip copy"; exit 1; }

echo "[INFO] Verifying cleanup..."
grep -q 'app.*_Dir' "$ADV_INST_CONFIG" && { echo "[ERROR] Residual app_Dir found"; exit 1; }
grep -q 'runtime.*_Dir' "$ADV_INST_CONFIG" && { echo "[ERROR] Residual runtime_Dir found"; exit 1; }
grep -q 'SourcePath=".*app' "$ADV_INST_CONFIG" && { echo "[ERROR] Residual app SourcePath found"; exit 1; }
grep -q 'SourcePath=".*runtime' "$ADV_INST_CONFIG" && { echo "[ERROR] Residual runtime SourcePath found"; exit 1; }

echo "[INFO] Checking paths for Advanced Installer CLI..."
echo "[DEBUG] ADV_INST_COM: $ADV_INST_COM" >> cleanup.log
if [ ! -f "$ADV_INST_COM" ]; then
    echo "[ERROR] Advanced Installer executable not found at $ADV_INST_COM"
    exit 1
fi
echo "[DEBUG] ADV_INST_CONFIG: $ADV_INST_CONFIG" >> cleanup.log
if [ ! -f "$ADV_INST_CONFIG" ]; then
    echo "[ERROR] .aip file not found at $ADV_INST_CONFIG"
    exit 1
fi
echo "[DEBUG] ADV_INST_SETUP_FILES/app: ${ADV_INST_SETUP_FILES}/app" >> cleanup.log
if [ ! -d "${ADV_INST_SETUP_FILES}/app" ]; then
    echo "[ERROR] Folder ${ADV_INST_SETUP_FILES}/app does not exist"
    exit 1
fi
echo "[DEBUG] ADV_INST_SETUP_FILES/runtime: ${ADV_INST_SETUP_FILES}/runtime" >> cleanup.log
if [ ! -d "${ADV_INST_SETUP_FILES}/runtime" ]; then
    echo "[ERROR] Folder ${ADV_INST_SETUP_FILES}/runtime does not exist"
    exit 1
fi

# Проверка валидности .aip файла
echo "[DEBUG] Checking .aip validity..." >> cleanup.log
if command -v xmllint >/dev/null; then
    xmllint --noout "$ADV_INST_CONFIG" 2>> cleanup.log || { echo "[ERROR] .aip file is not valid XML"; exit 1; }
else
    echo "[DEBUG] xmllint not found, skipping XML validation" >> cleanup.log
fi

# Копирование AdvancedInstaller.com в путь без пробелов
echo "[INFO] Copying AdvancedInstaller.com to C:\Temp to avoid spaces..."
mkdir -p "/c/Temp" || { echo "[ERROR] Failed to create C:\Temp"; exit 1; }
cp "$ADV_INST_COM" "/c/Temp/AdvancedInstaller.com" || { echo "[ERROR] Failed to copy AdvancedInstaller.com to C:\Temp"; exit 1; }
ADV_INST_COM="/c/Temp/AdvancedInstaller.com"
echo "[DEBUG] Updated ADV_INST_COM: $ADV_INST_COM" >> cleanup.log

# Преобразование путей в формат Windows
ADV_INST_COM_WIN=$(convert_path "$ADV_INST_COM")
ADV_INST_CONFIG_WIN=$(convert_path "$ADV_INST_CONFIG")
ADV_INST_SETUP_FILES_WIN=$(convert_path "$ADV_INST_SETUP_FILES")
echo "[DEBUG] Windows paths: ADV_INST_COM_WIN=\"$ADV_INST_COM_WIN\", ADV_INST_CONFIG_WIN=\"$ADV_INST_CONFIG_WIN\", ADV_INST_SETUP_FILES_WIN=\"$ADV_INST_SETUP_FILES_WIN\"" >> cleanup.log

# Установка английской локали для Advanced Installer
export LC_ALL=C

echo "[INFO] Attempting to remove old folders via AdvancedInstaller CLI..."
CLI_CMD="\"$ADV_INST_COM_WIN\" /edit \"$ADV_INST_CONFIG_WIN\" /DelFolder -path NewFolder_Dir\\app"
echo "[DEBUG] Executing: cmd.exe /C \"$CLI_CMD\"" >> cleanup.log
cmd.exe /C "$CLI_CMD" || echo "[WARN] Could not delete NewFolder_Dir\\app"
CLI_CMD="\"$ADV_INST_COM_WIN\" /edit \"$ADV_INST_CONFIG_WIN\" /DelFolder -path NewFolder_Dir\\runtime"
echo "[DEBUG] Executing: cmd.exe /C \"$CLI_CMD\"" >> cleanup.log
cmd.exe /C "$CLI_CMD" || echo "[WARN] Could not delete NewFolder_Dir\\runtime"

echo "[INFO] Adding new app and runtime folders to .aip..."
echo "[DEBUG] Checking source path for app: $ADV_INST_SETUP_FILES_WIN\\app" >> cleanup.log
if [ ! -d "$(echo "$ADV_INST_SETUP_FILES/app" | sed 's|\\|/|g')" ]; then
    echo "[ERROR] Source path for app does not exist: $ADV_INST_SETUP_FILES/app"
    exit 1
fi
CLI_CMD="\"$ADV_INST_COM_WIN\" /edit \"$ADV_INST_CONFIG_WIN\" /AddFolder -path NewFolder_Dir\\app -source \"$ADV_INST_SETUP_FILES_WIN\\app\""
echo "[DEBUG] Executing: cmd.exe /C \"$CLI_CMD\"" >> cleanup.log
cmd.exe /C "$CLI_CMD" || { echo "[ERROR] Failed to add app folder"; exit 1; }

echo "[DEBUG] Checking source path for runtime: $ADV_INST_SETUP_FILES_WIN\\runtime" >> cleanup.log
if [ ! -d "$(echo "$ADV_INST_SETUP_FILES/runtime" | sed 's|\\|/|g')" ]; then
    echo "[ERROR] Source path for runtime does not exist: $ADV_INST_SETUP_FILES/runtime"
    exit 1
fi
CLI_CMD="\"$ADV_INST_COM_WIN\" /edit \"$ADV_INST_CONFIG_WIN\" /AddFolder -path NewFolder_Dir\\runtime -source \"$ADV_INST_SETUP_FILES_WIN\\runtime\""
echo "[DEBUG] Executing: cmd.exe /C \"$CLI_CMD\"" >> cleanup.log
cmd.exe /C "$CLI_CMD" || { echo "[ERROR] Failed to add runtime folder"; exit 1; }

echo "[INFO] Building installer..."
CLI_CMD="\"$ADV_INST_COM_WIN\" /build \"$ADV_INST_CONFIG_WIN\""
echo "[DEBUG] Executing: cmd.exe /C \"$CLI_CMD\"" >> cleanup.log
cmd.exe /C "$CLI_CMD" || { echo "[ERROR] Build failed"; exit 1; }

echo "[INFO] Build completed successfully!"