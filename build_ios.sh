#!/bin/bash

# Get the branch name from the argument
BRANCH_NAME=$1

# Path to the Fastfile
FASTFILE_PATH="/Users/denispopkov/AndroidStudioProjects/SA_Neuro_Multiplatform/iosApp/fastlane/Fastfile"

# Update the Fastfile to set the branch name dynamically
sed -i "" "s/branch: 'soundcheck_develop'/branch: '$BRANCH_NAME'/g" "$FASTFILE_PATH"

# Navigate to the project directory
cd /Users/denispopkov/AndroidStudioProjects/SA_Neuro_Multiplatform/iosApp || exit

# Run the fastlane command
fastlane testflight_upload
