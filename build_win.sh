#!/bin/bash

# Load dependencies
source "./slack_upload.sh"
source "./utils.sh"

# Parameters
BRANCH_NAME=$1
isUseDevAnalytics=$2

# Configuration - using mixed paths that work in Git Bash
SECRET_FILE="/c/Users/BlackBricks/Desktop/secret.txt"
PROJECT_DIR="/c/Users/BlackBricks/StudioProjects/SA_Neuro_Multiplatform"
NEURO_WINDOW_FILE_PATH="$PROJECT_DIR/desktopApp/src/main/kotlin/presentation/neuro_window/NeuroWindow.kt"
NEURO_WINDOW_DSP_FILE="/c/Users/BlackBricks/Desktop/build_dsp/NeuroWindow.kt"
NEURO_WINDOW_N0_DSP_FILE="/c/Users/BlackBricks/Desktop/no_dsp/NeuroWindow.kt"
ERROR_LOG_FILE="${ERROR_LOG_FILE:-/tmp/build_error_log.txt}"  # Use environment variable or default

# Initialize error log
echo "Build started at $(date)" > "$ERROR_LOG_FILE"
echo "Branch: $BRANCH_NAME" >> "$ERROR_LOG_FILE"
echo "Dev Analytics: $isUseDevAnalytics" >> "$ERROR_LOG_FILE"

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
  local message=":x: Failed to build MacOS on \`$branch_name\`"
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

if [ "$isUseDevAnalytics" == "false" ]; then
  enable_prod_keys

  sleep 5

  powershell.exe -command "[System.Windows.Forms.SendKeys]::SendWait('^+O')"

  sleep 80
else
  echo "Nothing to change with analytics"
fi

# Replace NeuroWindow.kt before building
rm -f "$NEURO_WINDOW_FILE_PATH"
cp "$NEURO_WINDOW_N0_DSP_FILE" "$NEURO_WINDOW_FILE_PATH"

echo "Building MSI package..."
./gradlew packageReleaseMsi

# Restore original NeuroWindow.kt
rm -f "$NEURO_WINDOW_FILE_PATH"
cp "$NEURO_WINDOW_DSP_FILE" "$NEURO_WINDOW_FILE_PATH"

# Handle build output
DESKTOP_BUILD_PATH="$PROJECT_DIR/desktopApp/build/compose/binaries/main-release/msi"
FINAL_MSI_PATH="$DESKTOP_BUILD_PATH/Neuro Desktop-$VERSION_NAME.msi"
NEW_MSI_PATH="$DESKTOP_BUILD_PATH/Neuro_Desktop-$VERSION_NAME-$VERSION_CODE.msi"

if [ -f "$FINAL_MSI_PATH" ]; then
  if [ -f "$NEW_MSI_PATH" ]; then
    rm -f "$NEW_MSI_PATH"
    echo "Deleted existing file: $NEW_MSI_PATH"
  fi

  mv "$FINAL_MSI_PATH" "$NEW_MSI_PATH"
  echo "Renamed file to: $NEW_MSI_PATH"
else
  echo "Error: Build file not found at $FINAL_MSI_PATH"
  post_error_message "$BRANCH_NAME"
  exit 1
fi

sleep 20

echo "Uploading MSI to Slack..."
execute_file_upload "${SLACK_BOT_TOKEN}" "${SLACK_CHANNEL}" "Windows from $BRANCH_NAME" "upload" "${NEW_MSI_PATH}"
