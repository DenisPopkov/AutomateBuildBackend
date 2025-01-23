#!/bin/bash

source "/Users/denispopkov/PycharmProjects/AutomateBuildBackend/slack_upload.sh"

# Assuming the file path is passed as the first argument to the script
FILE_PATH="$1"
SECRET_FILE="/Users/denispopkov/Desktop/secret.txt"

# Check if the secret.txt file exists
if [ ! -f "$SECRET_FILE" ]; then
  echo "Error: secret.txt file not found at $SECRET_FILE"
  exit 1
fi

# Read the secrets
while IFS='=' read -r key value; do
  key=$(echo "$key" | xargs)
  value=$(echo "$value" | xargs)

  case "$key" in
    "SLACK_BOT_TOKEN") SLACK_BOT_TOKEN="$value" ;;
    "SLACK_CHANNEL") SLACK_CHANNEL="$value" ;;
  esac
done < "$SECRET_FILE"

# Slack Upload
echo "Uploading file to Slack..."
execute_file_upload "${SLACK_BOT_TOKEN}" "${SLACK_CHANNEL}" "test" "${FILE_PATH}"

if [ $? -eq 0 ]; then
    echo "File sent to Slack successfully."
else
    echo "Error sending file to Slack."
    exit 1
fi
