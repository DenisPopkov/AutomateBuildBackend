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

convert_path() {
    local path="$1"
    if command -v cygpath >/dev/null; then
        cygpath -w "$path" | sed 's|\\|\\\\|g'
    else
        echo "$path" | sed 's|^/c/|C:\\\\|; s|/|\\\\|g'
    fi
}

# Проверка ошибок в логе
check_error_log() {
    if [ -s "$ERROR_LOG_FILE" ]; then
        echo "[ERROR] Ошибка в $ERROR_LOG_FILE:"
        cat "$ERROR_LOG_FILE"
        exit 1
    fi
}

# Проверка валидности .aip файла
validate_aip() {
    local aip_file="$1"
    echo "[INFO] Проверяем валидность $aip_file..."
    if ! "$XMLSTARLET_PATH" val "$aip_file" 2>> "$ERROR_LOG_FILE"; then
        echo "[ERROR] Файл $aip_file невалиден"
        cat "$ERROR_LOG_FILE"
        exit 1
    fi
}

# Удаление директории и связанных компонентов
remove_directory() {
    local dir_id="$1"
    echo "[INFO] Удаляем $dir_id из .aip..."

    # Удаляем из таблицы Directory
    "$XMLSTARLET_PATH" ed --inplace \
        -d "//TABLE[@Name='Directory']/ROW[@Directory='$dir_id']" \
        "$ADV_INST_CONFIG" 2>> "$ERROR_LOG_FILE"
    check_error_log

    # Удаляем компоненты, связанные с директорией
    "$XMLSTARLET_PATH" ed --inplace \
        -d "//TABLE[@Name='Component']/ROW[@Directory_='$dir_id']" \
        "$ADV_INST_CONFIG" 2>> "$ERROR_LOG_FILE"
    check_error_log

    # Удаляем связи в FeatureComponents
    "$XMLSTARLET_PATH" ed --inplace \
        -d "//TABLE[@Name='FeatureComponents']/ROW[@Component_='$dir_id']" \
        "$ADV_INST_CONFIG" 2>> "$ERROR_LOG_FILE"
    check_error_log

    # Удаляем файлы, связанные с компонентами в этой директории
    "$XMLSTARLET_PATH" ed --inplace \
        -d "//TABLE[@Name='File']/ROW[Component_/ancestor::TABLE[@Name='Component']/ROW[@Directory_='$dir_id']]" \
        "$ADV_INST_CONFIG" 2>> "$ERROR_LOG_FILE"
    check_error_log
}

# Добавление директории в таблицу Directory
add_directory() {
    local dir_id="$1"
    local parent_dir="$2"
    local default_dir="$3"
    echo "[INFO] Добавляем директорию $dir_id в $parent_dir..."

    "$XMLSTARLET_PATH" ed --inplace \
        -s "//TABLE[@Name='Directory']" -t elem -n ROW \
        -i "//TABLE[@Name='Directory']/ROW[last()]" -t attr -n Directory -v "$dir_id" \
        -i "//TABLE[@Name='Directory']/ROW[last()]" -t attr -n Directory_Parent -v "$parent_dir" \
        -i "//TABLE[@Name='Directory']/ROW[last()]" -t attr -n DefaultDir -v "$default_dir" \
        "$ADV_INST_CONFIG" 2>> "$ERROR_LOG_FILE"
    check_error_log
}

# Добавление файлов в указанную директорию
add_files_to_dir() {
    local source_dir="$1"
    local dir_id="$2"
    local component_name="${dir_id}_component"
    echo "[INFO] Добавляем файлы из $source_dir в $dir_id..."

    if [ ! -d "$source_dir" ]; then
        echo "[ERROR] Папка $source_dir не найдена"
        exit 1
    fi

    # Создаем компонент для директории
    if ! "$XMLSTARLET_PATH" sel -t -v "//TABLE[@Name='Component']/ROW[@Component='$component_name']" "$ADV_INST_CONFIG" | grep -q .; then
        "$XMLSTARLET_PATH" ed --inplace \
            -s "//TABLE[@Name='Component']" -t elem -n ROW \
            -i "//TABLE[@Name='Component']/ROW[last()]" -t attr -n Component -v "$component_name" \
            -i "//TABLE[@Name='Component']/ROW[last()]" -t attr -n ComponentId -v "{$(powershell.exe "[guid]::NewGuid().ToString()" | tr -d '\r')}" \
            -i "//TABLE[@Name='Component']/ROW[last()]" -t attr -n Directory_ -v "$dir_id" \
            -i "//TABLE[@Name='Component']/ROW[last()]" -t attr -n Attributes -v "0" \
            -i "//TABLE[@Name='Component']/ROW[last()]" -t attr -n KeyPath -v "" \
            "$ADV_INST_CONFIG" 2>> "$ERROR_LOG_FILE"
        check_error_log

        # Добавляем компонент в FeatureComponents
        "$XMLSTARLET_PATH" ed --inplace \
            -s "//TABLE[@Name='FeatureComponents']" -t elem -n ROW \
            -i "//TABLE[@Name='FeatureComponents']/ROW[last()]" -t attr -n Feature_ -v "MainFeature" \
            -i "//TABLE[@Name='FeatureComponents']/ROW[last()]" -t attr -n Component_ -v "$component_name" \
            "$ADV_INST_CONFIG" 2>> "$ERROR_LOG_FILE"
        check_error_log
    fi

    # Добавляем файлы
    while IFS= read -r -d '' file; do
        local filename=$(basename "$file")
        local shortname=$(echo "$filename" | cut -c1-8 | tr '[:lower:]' '[:upper:]' | sed 's/[^A-Z0-9]//g')
        shortname="${shortname}~1.${filename##*.}"
        local file_id=$(echo "$filename" | tr -d '.-' | tr '[:upper:]' '[:lower:]')
        local attributes=$([[ "$filename" == *.dll ]] && echo "256" || echo "0")
        local file_win_path=$(convert_path "$file")

        echo "[DEBUG] Добавляем файл: $filename"

        # Добавляем файл в таблицу File
        "$XMLSTARLET_PATH" ed --inplace \
            -s "//TABLE[@Name='File']" -t elem -n ROW \
            -i "//TABLE[@Name='File']/ROW[last()]" -t attr -n File -v "$file_id" \
            -i "//TABLE[@Name='File']/ROW[last()]" -t attr -n Component_ -v "$component_name" \
            -i "//TABLE[@Name='File']/ROW[last()]" -t attr -n FileName -v "${shortname}|${filename}" \
            -i "//TABLE[@Name='File']/ROW[last()]" -t attr -n Attributes -v "$attributes" \
            -i "//TABLE[@Name='File']/ROW[last()]" -t attr -n SourcePath -v "$file_win_path" \
            -i "//TABLE[@Name='File']/ROW[last()]" -t attr -n SelfReg -v "false" \
            "$ADV_INST_CONFIG" 2>> "$ERROR_LOG_FILE"
        check_error_log
    done < <(find "$source_dir" -type f -print0)
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

# Проверяем валидность исходного .aip файла
echo "[INFO] Checking for xmlstarlet..."
XMLSTARLET_PATH="/c/ProgramData/chocolatey/bin/xmlstarlet.exe"
if [ ! -x "$XMLSTARLET_PATH" ]; then
    echo "[ERROR] xmlstarlet is not installed or not executable at $XMLSTARLET_PATH"
    exit 1
fi
validate_aip "$ADV_INST_CONFIG"

echo "[INFO] Updating version and product code..."
sed -i "s/\(Property=\"ProductVersion\" Value=\"\)[^\"]*\(\".*\)/\1${VERSION_NAME}\2/" "$ADV_INST_CONFIG"
NEW_GUID=$(powershell.exe "[guid]::NewGuid().ToString()" | tr -d '\r')
[ -z "$NEW_GUID" ] && { echo "[ERROR] Failed to generate ProductCode"; exit 1; }
sed -i "s/\(Property=\"ProductCode\" Value=\"\)[^\"]*\(\".*\)/\1${NEW_GUID}\2/" "$ADV_INST_CONFIG"
sed -i "s/\(PackageFileName=\"Neuro_Desktop-\)[^\"]*\(\".*\)/\1${VERSION_NAME}-${VERSION_CODE}\2/" "$ADV_INST_CONFIG"

echo "[INFO] Cleaning up existing app_Dir and runtime_Dir..."
remove_directory "app_Dir"
remove_directory "runtime_Dir"

echo "[INFO] Adding new app_Dir and runtime_Dir..."
add_directory "app_Dir" "NewFolder_Dir" "app"
add_directory "runtime_Dir" "NewFolder_Dir" "runtime"

echo "[INFO] Adding files to app_Dir..."
add_files_to_dir "${ADV_INST_SETUP_FILES}/app" "app_Dir"

echo "[INFO] Adding files to runtime_Dir..."
add_files_to_dir "${ADV_INST_SETUP_FILES}/runtime" "runtime_Dir"

echo "[INFO] Checking modified .aip file..."
validate_aip "$ADV_INST_CONFIG"

WIN_AIP_PATH=$(convert_path "$ADV_INST_CONFIG")
echo "[DEBUG] Используемый путь для Advanced Installer: $WIN_AIP_PATH"

if [ ! -f "$ADV_INST_CONFIG" ]; then
    echo "[ERROR] Файл $ADV_INST_CONFIG не существует"
    exit 1
fi

ADV_INST_PATH="C:/Program Files (x86)/Caphyon/Advanced Installer 22.6/bin/x86/AdvancedInstaller.com"
if [ ! -f "$ADV_INST_PATH" ]; then
    echo "[ERROR] Advanced Installer не найден по пути $ADV_INST_PATH"
    exit 1
fi

echo "[INFO] Building MSI with Advanced Installer..."
echo "[DEBUG] Выполняемая команда: cmd.exe /c \"$ADV_INST_PATH\" /build \"$WIN_AIP_PATH\""
cmd.exe /c "\"$ADV_INST_PATH\" /build \"$WIN_AIP_PATH\"" 2>> "$ERROR_LOG_FILE" || { echo "[ERROR] Не удалось собрать MSI"; cat "$ERROR_LOG_FILE"; exit 1; }

echo "[INFO] Cleaning up temporary files..."
rm -rf "${ADV_INST_SETUP_FILES}/app"
rm -rf "${ADV_INST_SETUP_FILES}/runtime"

echo "[INFO] Build completed successfully."
#SIGNED_MSI_PATH="$ADVANCED_INSTALLER_MSI_FILES/Neuro_Desktop-${VERSION_NAME}-${VERSION_CODE}.msi"
# signtool sign /fd sha256 /tr http://ts.ssl.com /td sha256 /sha1 20fbd34014857033bcc6dabfae390411b22b0b1e "$SIGNED_MSI_PATH"

#echo "Uploading signed MSI to Slack: $SIGNED_MSI_PATH"
#execute_file_upload "$SLACK_BOT_TOKEN" "$SLACK_CHANNEL" ":white_check_mark: Windows build for \`$BRANCH_NAME\`" "upload" "$SIGNED_MSI_PATH"
#delete_message "$SLACK_BOT_TOKEN" "$SLACK_CHANNEL" "$first_ts"
