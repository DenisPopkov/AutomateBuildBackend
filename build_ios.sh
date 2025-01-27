#!/bin/bash

BRANCH_NAME=$1

FASTFILE_PATH="/Users/denispopkov/AndroidStudioProjects/SA_Neuro_Multiplatform/iosApp/fastlane/Fastfile"

cd /Users/denispopkov/AndroidStudioProjects/SA_Neuro_Multiplatform/iosApp || exit

fastlane testflight_upload
