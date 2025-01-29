#!/bin/bash

source "/Users/denispopkov/PycharmProjects/AutomateBuildBackend/slack_upload.sh"

FILE_PATH="$1"
SECRET_FILE="/Users/denispopkov/Desktop/secret.txt"

while IFS='=' read -r key value; do
  key=$(echo "$key" | xargs)
  value=$(echo "$value" | xargs)

  case "$key" in
    "SLACK_BOT_TOKEN") SLACK_BOT_TOKEN="$value" ;;
    "SLACK_CHANNEL") SLACK_CHANNEL="$value" ;;
  esac
done < "$SECRET_FILE"

# Upload to Slack
echo "Uploading file to Slack..."
execute_file_upload "${SLACK_BOT_TOKEN}" "${SLACK_CHANNEL}" "Uploaded from builds" "upload" "${FILE_PATH}"

if [ $? -eq 0 ]; then
    echo "File sent to Slack successfully."
else
    echo "Error sending file to Slack."
    exit 1
fi
