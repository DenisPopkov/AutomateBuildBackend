#!/bin/bash

set -e

AIP_FILE="/c/Users/BlackBricks/Applications/Neuro installer/installer_win/Neuro Desktop 2.aip"
APP_DIR="/c/Users/BlackBricks/Applications/Neuro installer/app"

if [ ! -f "$AIP_FILE" ]; then
    echo "[ERROR] AIP file not found: $AIP_FILE"
    exit 1
fi

if [ ! -d "$APP_DIR" ]; then
    echo "[ERROR] App directory not found: $APP_DIR"
    exit 1
fi

update_aip_jar_references() {
    local aip_file="$1"
    local app_dir="$2"

    echo "[INFO] Updating .jar file references in $aip_file from $app_dir"

    for jar in "$app_dir"/*.jar; do
        local base_name
        base_name=$(basename "$jar")

        local prefix
        prefix=$(echo "$base_name" | sed -E 's/-[0-9a-f]{32}\.jar$//')

        if [[ "$prefix" == "$base_name" ]]; then
            echo "[WARNING] $base_name does not match expected pattern, skipping"
            continue
        fi

        echo "[INFO] Updating references for $prefix"

        # Удаляем старые ссылки
        sed -i "/<ROW File=\"${prefix//./\\.}.*\.jar\" .*SourcePath=\"..\\\\app\\\\${prefix//./\\.}.*\.jar\"/d" "$aip_file"

        # Добавляем новую строку (примерная схема)
        local new_row="<ROW File=\"${base_name//./}0\" Component_=\"maincomponent\" FileName=\"${base_name^^}\" Attributes=\"0\" SourcePath=\"..\\\\app\\\\$base_name\" SelfReg=\"false\"/>"

        sed -i "0,/<ROW /s//${new_row}\n&/" "$aip_file"
    done

    echo "[INFO] All .jar references updated"
}

update_aip_jar_references "$AIP_FILE" "$APP_DIR"

echo "[INFO] Done. Please check $AIP_FILE manually."
