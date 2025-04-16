#!/bin/bash

source "/Users/denispopkov/PycharmProjects/AutomateBuildBackend/slack_upload.sh"
source "/Users/denispopkov/PycharmProjects/AutomateBuildBackend/utils.sh"

BRANCH_NAME=$1
isUseDevAnalytics=$2

SECRET_FILE="/Users/denispopkov/Desktop/secret.txt"
ERROR_LOG_FILE="/tmp/build_error_log.txt"

if [ -z "$BRANCH_NAME" ]; then
  echo "Usage: $0 <branch-name>"
  exit 1
fi

if [ ! -f "$SECRET_FILE" ]; then
  echo "Error: secret.txt file not found at $SECRET_FILE"
  exit 1
fi

while IFS='=' read -r key value; do
  key=$(echo "$key" | xargs)
  value=$(echo "$value" | xargs)

  case "$key" in
    "SLACK_BOT_TOKEN") SLACK_BOT_TOKEN="$value" ;;
    "SLACK_CHANNEL") SLACK_CHANNEL="$value" ;;
    "TEAM_ID") TEAM_ID="$value" ;;
    "GITHUB_TOKEN") GITHUB_TOKEN="$value" ;;
    "REPO_OWNER") REPO_OWNER="$value" ;;
    "REPO_NAME") REPO_NAME="$value" ;;
  esac
done < "$SECRET_FILE"

open -a "Android Studio"

PROJECT_DIR="/Users/denispopkov/AndroidStudioProjects/SA_Neuro_Multiplatform"
cd "$PROJECT_DIR" || { echo "Project directory not found!"; exit 1; }

echo "Checking out branch: $BRANCH_NAME"
git stash push -m "Pre-build stash"
git fetch && git checkout "$BRANCH_NAME" && git pull origin "$BRANCH_NAME" --no-rebase

VERSION_CODE=$(grep '^desktop\.build\.number\s*=' "$PROJECT_DIR/gradle.properties" | sed 's/.*=\s*\([0-9]*\)/\1/' | xargs)
VERSION_CODE=$((VERSION_CODE + 1))

analyticsMessage=""

if [ "$isUseDevAnalytics" == "true" ]; then
  analyticsMessage="dev"
else
  analyticsMessage="prod"
fi

end_time=$(TZ=Asia/Omsk date -v+25M "+%H:%M")
message=":hammer_and_wrench: Windows build started on \`$BRANCH_NAME\`
:mag_right: Analytics look on $analyticsMessage
:clock2: It will be ready approximately at $end_time"
post_message "${SLACK_BOT_TOKEN}" "${SLACK_CHANNEL}" "$message"

if [ "$isUseDevAnalytics" == "false" ]; then
  enable_prod_keys
else
  echo "Nothing to change with analytics"
fi

sed -i '' "s/^desktop\.build\.number\s*=\s*[0-9]*$/desktop.build.number=$VERSION_CODE/" "$PROJECT_DIR/gradle.properties"
git pull origin "$BRANCH_NAME" --no-rebase
git add .
git commit -m "add: Windows version bump"
git push origin "$BRANCH_NAME"

sleep 10

WORKFLOW_FILENAME="build_windows.yml"

curl -X POST \
  -H "Authorization: Bearer $GITHUB_TOKEN" \
  -H "Accept: application/vnd.github+json" \
  https://api.github.com/repos/"$REPO_OWNER"/"$REPO_NAME"/actions/workflows/$WORKFLOW_FILENAME/dispatches \
  -d "{\"ref\":\"$BRANCH_NAME\"}" \
  || echo "❌ Failed to trigger workflow" >> "$ERROR_LOG_FILE"

sleep 1000

if [ "$isUseDevAnalytics" == "false" ]; then
  undo_enable_prod_keys

  sleep 10

  git pull origin "$BRANCH_NAME" --no-rebase
  git add .
  git commit -m "add: revoke prod analytics"
  git push origin "$BRANCH_NAME"
else
  echo "Nothing to change with analytics"
fi
