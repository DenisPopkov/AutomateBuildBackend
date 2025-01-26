#!/bin/bash

BRANCH_NAME=$1

FASTFILE_PATH="/Users/denispopkov/AndroidStudioProjects/SA_Neuro_Multiplatform/iosApp/fastlane/Fastfile"

# Update the Fastfile to set the branch name dynamically
sed -i "" "s/branch: 'soundcheck_develop'/branch: '$BRANCH_NAME'/g" "$FASTFILE_PATH"

cd /Users/denispopkov/AndroidStudioProjects/SA_Neuro_Multiplatform/iosApp || exit

fastlane testflight_upload
