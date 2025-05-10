#!/bin/bash

export LC_ALL=C.UTF-8
export LANG=C.UTF-8

source "./slack_upload.sh"
source "./utils.sh"

BRANCH_NAME=$1
isUseDevAnalytics=$2

SECRET_FILE="/c/Users/BlackBricks/Desktop/secret.txt"
ERROR_LOG_FILE="${ERROR_LOG_FILE:-/tmp/build_error_log.txt}"
PROJECT_DIR="/c/Users/BlackBricks/StudioProjects/SA_Neuro_Multiplatform"
ADV_INST_CONFIG="/c/Users/BlackBricks/Applications/Neuro installer/installer_win/Neuro Desktop 2.aip"
ADV_INST_SETUP_FILES="/c/Users/BlackBricks/Applications/Neuro installer"
ADVANCED_INSTALLER_MSI_FILES="/c/Users/BlackBricks/Applications/Neuro installer/installer_win/Neuro Desktop-SetupFiles"

# Проверка зависимостей
LESSMSI="/c/ProgramData/chocolatey/bin/lessmsi.exe"
ADV_INST_PATH="C:/Program Files (x86)/Caphyon/Advanced Installer 22.6/bin/x86/AdvancedInstaller.com"
XMLSTARLET="/c/ProgramData/chocolatey/bin/xmlstarlet.exe"

check_dependencies() {
    for tool in "$LESSMSI" "$ADV_INST_PATH" "$XMLSTARLET"; do
        if [ ! -f "$tool" ]; then
            echo "[ERROR] Tool not found: $tool"
            exit 1
        fi
    done
}

convert_path() {
    local path="$1"
    if command -v cygpath >/dev/null; then
        cygpath -w "$path"
    else
        echo "$path" | sed 's|^/c/|C:\\|; s|/|\\|g'
    fi
}

check_error_log() {
    if [ -s "$ERROR_LOG_FILE" ]; then
        echo "[ERROR] Ошибка в $ERROR_LOG_FILE:"
        cat "$ERROR_LOG_FILE"
        exit 1
    fi
}

# Проверка входных аргументов
if [ -z "$BRANCH_NAME" ]; then
    echo "[ERROR] Branch name not provided"
    exit 1
fi

# Проверка зависимостей
check_dependencies

# Переход в директорию проекта
cd "$PROJECT_DIR" || { echo "[ERROR] Failed to change directory to $PROJECT_DIR"; exit 1; }

# Получение версии из gradle.properties
VERSION_CODE=$(grep '^desktop\.build\.number\s*=' gradle.properties | sed 's/.*=\s*\([0-9]*\)/\1/' | xargs)
VERSION_NAME=$(grep '^desktop\.version\s*=' gradle.properties | sed 's/.*=\s*\([0-9]*\.[0-9]*\.[0-9]*\)/\1/' | xargs)
if [ -z "$VERSION_CODE" ] || [ -z "$VERSION_NAME" ]; then
    echo "[ERROR] Failed to parse version from gradle.properties"
    exit 1
fi
echo "[INFO] Version: $VERSION_NAME, Build: $VERSION_CODE"

# Закомментированная часть для работы с Git и Slack
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
#git stash push -m "Pre-build stash"
#git fetch --all
#git checkout "$BRANCH_NAME"
#git pull origin "$BRANCH_NAME" --no-rebase
#
#VERSION_CODE=$((VERSION_CODE + 1))
#
#sed -i "s/^desktop\.build\.number\s*=\s*[0-9]*$/desktop.build.number=$VERSION_CODE/" gradle.properties
#git add gradle.properties
#git commit -m "Windows version bump to $VERSION_CODE"
#git push origin "$BRANCH_NAME"
#
#analyticsMessage="prod"
#[ "$isUseDevAnalytics" == "true" ] && analyticsMessage="dev"
#
#end_time=$(date -d "+15 minutes" +"%H:%M")
#message=":hammer_and_wrench: Windows build started on \`$BRANCH_NAME\` with $analyticsMessage analytics. It will be ready approximately at $end_time"
#first_ts=$(post_message "$SLACK_BOT_TOKEN" "$SLACK_CHANNEL" "$message")
#
#if [ "$isUseDevAnalytics" == "false" ]; then
#  enable_prod_keys
#  sleep 5
#  powershell -command "Add-Type -AssemblyName System.Windows.Forms; [System.Windows.Forms.SendKeys]::SendWait('^(+o)')"
#  sleep-protector 50
#fi
#
#./gradlew packageReleaseMsi || { post_error_message "$BRANCH_NAME"; exit 1; }

# Поиск MSI файла
DESKTOP_BUILD_PATH="$PROJECT_DIR/desktopApp/build/compose/binaries/main-release/msi"
MSI_FILE=$(find "$DESKTOP_BUILD_PATH" -name "Neuro*.msi" | head -n 1)
if [ -z "$MSI_FILE" ]; then
    echo "[ERROR] MSI file not found in $DESKTOP_BUILD_PATH"
    exit 1
fi
echo "[INFO] Found MSI: $MSI_FILE"

# Переименование MSI файла
NEW_MSI_PATH="$DESKTOP_BUILD_PATH/Neuro_Desktop-${VERSION_NAME}-${VERSION_CODE}.msi"
[ -f "$NEW_MSI_PATH" ] && rm -f "$NEW_MSI_PATH"
mv "$MSI_FILE" "$NEW_MSI_PATH" || { echo "[ERROR] Failed to rename MSI"; exit 1; }
echo "[INFO] Renamed MSI to: $NEW_MSI_PATH"

# Извлечение MSI
MSI_WIN_PATH=$(convert_path "$NEW_MSI_PATH")
echo "[INFO] Extracting MSI: $MSI_WIN_PATH"
"$LESSMSI" x "$MSI_WIN_PATH" 2>> "$ERROR_LOG_FILE" || { echo "[ERROR] Failed to extract MSI"; cat "$ERROR_LOG_FILE"; exit 1; }
check_error_log

EXTRACT_DIR="/c/Users/BlackBricks/StudioProjects/SA_Neuro_Multiplatform/Neuro_Desktop-${VERSION_NAME}-${VERSION_CODE}/SourceDir/Neuro Desktop"
if [ ! -d "$EXTRACT_DIR" ]; then
    echo "[ERROR] Extracted directory not found: $EXTRACT_DIR"
    exit 1
fi
echo "[INFO] MSI extracted to: $EXTRACT_DIR"

# Удаление старых папок
echo "[INFO] Removing old app and runtime folders..."
[ -d "${ADV_INST_SETUP_FILES}/app" ] && rm -rf "${ADV_INST_SETUP_FILES}/app" && echo "[INFO] App folder removed" || echo "[INFO] App folder does not exist"
[ -d "${ADV_INST_SETUP_FILES}/runtime" ] && rm -rf "${ADV_INST_SETUP_FILES}/runtime" && echo "[INFO] Runtime folder removed" || echo "[INFO] Runtime folder does not exist"

# Копирование новых папок
echo "[INFO] Copying new app and runtime folders..."
cp -rf "${EXTRACT_DIR}/app" "${ADV_INST_SETUP_FILES}/app" || { echo "[ERROR] Failed to copy 'app' folder"; exit 1; }
if [ -d "${ADV_INST_SETUP_FILES}/app" ]; then
    echo "[INFO] App folder copied"
else
    echo "[ERROR] App folder not found after copy"
    exit 1
fi

cp -rf "${EXTRACT_DIR}/runtime" "${ADV_INST_SETUP_FILES}/runtime" || { echo "[ERROR] Failed to copy 'runtime' folder"; exit 1; }
if [ -d "${ADV_INST_SETUP_FILES}/runtime" ]; then
    echo "[INFO] Runtime folder copied"
else
    echo "[ERROR] Runtime folder not found after copy"
    exit 1
fi

# Обновление версии и ProductCode с использованием xmlstarlet
echo "[INFO] Updating version and product code in $ADV_INST_CONFIG..."
"$XMLSTARLET" ed -u "//ROW[@Property='ProductVersion']/@Value" -v "${VERSION_NAME}" "$ADV_INST_CONFIG" > temp.aip && mv temp.aip "$ADV_INST_CONFIG" || { echo "[ERROR] Failed to update ProductVersion"; exit 1; }
NEW_GUID=$(powershell.exe "[guid]::NewGuid().ToString()" | tr -d '\r')
if [ -z "$NEW_GUID" ]; then
    echo "[ERROR] Failed to generate ProductCode"
    exit 1
fi
"$XMLSTARLET" ed -u "//ROW[@Property='ProductCode']/@Value" -v "${NEW_GUID}" "$ADV_INST_CONFIG" > temp.aip && mv temp.aip "$ADV_INST_CONFIG" || { echo "[ERROR] Failed to update ProductCode"; exit 1; }
"$XMLSTARLET" ed -u "//ROW[@Property='PackageFileName']/@Value" -v "Neuro_Desktop-${VERSION_NAME}-${VERSION_CODE}" "$ADV_INST_CONFIG" > temp.aip && mv temp.aip "$ADV_INST_CONFIG" || { echo "[ERROR] Failed to update PackageFileName"; exit 1; }

# Сборка MSI
echo "[INFO] Building MSI with Advanced Installer..."
cmd.exe /c "\"$ADV_INST_PATH\" /build \"$(convert_path "$ADV_INST_CONFIG")\"" 2>> "$ERROR_LOG_FILE" || { echo "[ERROR] Не удалось собрать MSI"; cat "$ERROR_LOG_FILE"; exit 1; }
check_error_log

echo "[INFO] Build completed successfully."

# Закомментированная часть для подписи MSI и загрузки в Slack
#SIGNED_MSI_PATH="$ADVANCED_INSTALLER_MSI_FILES/Neuro_Desktop-${VERSION_NAME}-${VERSION_CODE}.msi"
#signtool sign /fd sha256 /tr http://ts.ssl.com /td sha256 /sha1 20fbd34014857033bcc6dabfae390411b22b0b1e "$SIGNED_MSI_PATH"
#
#echo "Uploading signed MSI to Slack: $SIGNED_MSI_PATH"
#execute_file_upload "$SLACK_BOT_TOKEN" "$SLACK_CHANNEL" ":white_check_mark: Windows build for \`$BRANCH_NAME\`" "upload" "$SIGNED_MSI_PATH"
#delete_message "$SLACK_BOT_TOKEN" "$SLACK_CHANNEL" "$first_ts"