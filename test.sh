#!/bin/bash

source "/Users/denispopkov/PycharmProjects/AutomateBuildBackend/slack_upload.sh"
source "/Users/denispopkov/PycharmProjects/AutomateBuildBackend/utils.sh"

PROJECT_DIR="/Users/denispopkov/AndroidStudioProjects/SA_Neuro_Multiplatform"

cd "$PROJECT_DIR" || { echo "Project directory not found!"; exit 1; }

echo "Opening Android Studio..."
open -a "Android Studio"

comment_desktop_build_native_lib
