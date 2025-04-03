#!/bin/bash

source "./slack_upload.sh"
source "./utils.sh"

BRANCH_NAME=$1
isUseDevAnalytics=$2

SECRET_FILE="/c/Users/BlackBricks/Desktop/secret.txt"
PROJECT_DIR="/c/Users/BlackBricks/StudioProjects/SA_Neuro_Multiplatform"
NEURO_WINDOW_KT="$PROJECT_DIR/desktopApp/src/main/kotlin/presentation/neuro_window/NeuroWindow.kt"
SET_UPDATED_LIB_PATH="$PROJECT_DIR/shared/src/commonMain/resources/MR/files/libs/dspmac.dll"
CACHE_UPDATED_LIB_PATH="$PROJECT_DIR/desktopApp/resources/common/dsp/Debug/dspmac.dll"
ERROR_LOG_FILE="${ERROR_LOG_FILE:-/tmp/build_error_log.txt}"

while IFS='=' read -r key value; do
  key=$(echo "$key" | xargs)
  value=$(echo "$value" | xargs)

  case "$key" in
    "SLACK_BOT_TOKEN") SLACK_BOT_TOKEN="$value" ;;
    "SLACK_CHANNEL") SLACK_CHANNEL="$value" ;;
  esac
done < "$SECRET_FILE"

post_error_message() {
  local branch_name=$1
  local message=":x: Failed to build Windows on \`$branch_name\`"
  execute_file_upload "${SLACK_BOT_TOKEN}" "${SLACK_CHANNEL}" "$message" "upload" "$ERROR_LOG_FILE"
}

echo "Opening Android Studio..."
"/c/Program Files/Android/Android Studio/bin/studio64.exe" &

cd "$PROJECT_DIR" || { echo "Project directory not found!"; exit 1; }

echo "Checking out branch: $BRANCH_NAME"
git stash push -m "Pre-build stash"
git fetch && git checkout "$BRANCH_NAME" && git pull origin "$BRANCH_NAME" --no-rebase

# Extract version info
VERSION_CODE=$(grep '^desktop\.build\.number\s*=' "$PROJECT_DIR/gradle.properties" | sed 's/.*=\s*\([0-9]*\)/\1/' | xargs)
VERSION_NAME=$(grep '^desktop\.version\s*=' "$PROJECT_DIR/gradle.properties" | sed 's/.*=\s*\([0-9]*\.[0-9]*\.[0-9]*\)/\1/' | xargs)

VERSION_CODE=$((VERSION_CODE + 1))
sed -i "s/^desktop\.build\.number\s*=\s*[0-9]*$/desktop.build.number=$VERSION_CODE/" "$PROJECT_DIR/gradle.properties"
git pull origin "$BRANCH_NAME" --no-rebase
git add .
git commit -m "Windows version bump to $VERSION_CODE"
git push origin "$BRANCH_NAME"

analyticsMessage=""

if [ "$isUseDevAnalytics" == "true" ]; then
  analyticsMessage="dev"
else
  analyticsMessage="prod"
fi

end_time=$(date -d "+15 minutes" +"%H:%M")
message=":hammer_and_wrench: Windows build started on \`$BRANCH_NAME\`
:mag_right: Analytics look on $analyticsMessage
:clock2: It will be ready approximately at $end_time"
post_message "${SLACK_BOT_TOKEN}" "${SLACK_CHANNEL}" "$message"

enable_dsp_gradle_task

sleep 5

powershell -command "\
Add-Type -AssemblyName System.Windows.Forms; \
[System.Windows.Forms.SendKeys]::SendWait('^(+o)'); \
Start-Sleep -Milliseconds 100"

sleep 80

if ! ./gradlew compileKotlin --stacktrace --info; then
  echo "Error: Gradle build failed"
  post_error_message "$BRANCH_NAME"
  disable_dsp_gradle_task
  exit 1
fi

sleep 5

disable_dsp_gradle_task

rm -f "$SET_UPDATED_LIB_PATH"
cp "$CACHE_UPDATED_LIB_PATH" "$SET_UPDATED_LIB_PATH"

sleep 10

git pull origin "$BRANCH_NAME" --no-rebase
git add .
git commit -m "add: update Windows DSP lib"
git push origin "$BRANCH_NAME"

sleep 10

if [ "$isUseDevAnalytics" == "false" ]; then
  enable_prod_keys

  sleep 5

  powershell -command "\
  Add-Type -AssemblyName System.Windows.Forms; \
  [System.Windows.Forms.SendKeys]::SendWait('^(+o)'); \
  Start-Sleep -Milliseconds 100"

  sleep 80
else
  echo "Nothing to change with analytics"
fi

echo "Building MSI package..."
./gradlew packageReleaseMsi

DESKTOP_BUILD_PATH="$PROJECT_DIR/desktopApp/build/compose/binaries/main-release/msi"

# Check for the MSI file (handle spaces in filename)
MSI_FILE=$(find "$DESKTOP_BUILD_PATH" -name "Neuro*.msi" | head -n 1)

if [ -z "$MSI_FILE" ]; then
    echo "Error: No MSI file found in $DESKTOP_BUILD_PATH"
    post_error_message "$BRANCH_NAME"
    exit 1
fi

# Define the new filename (Neuro_Desktop-<version>-<build>.msi)
NEW_MSI_PATH="$DESKTOP_BUILD_PATH/Neuro_Desktop-${VERSION_NAME}-${VERSION_CODE}.msi"

# Remove existing file if present
if [ -f "$NEW_MSI_PATH" ]; then
    rm -f "$NEW_MSI_PATH"
    echo "Deleted existing file: $NEW_MSI_PATH"
fi

# Rename the MSI file
mv "$MSI_FILE" "$NEW_MSI_PATH"
echo "Renamed file to: $NEW_MSI_PATH"

# Upload to Slack
echo "Uploading MSI to Slack..."
execute_file_upload "${SLACK_BOT_TOKEN}" "${SLACK_CHANNEL}" ":white_check_mark: Windows from \`$BRANCH_NAME\`" "upload" "$NEW_MSI_PATH"
