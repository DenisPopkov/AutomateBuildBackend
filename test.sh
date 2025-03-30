#!/bin/bash

source "/Users/denispopkov/PycharmProjects/AutomateBuildBackend/slack_upload.sh"
source "/Users/denispopkov/PycharmProjects/AutomateBuildBackend/utils.sh"

SECRET_FILE="/Users/denispopkov/Desktop/secret.txt"

while IFS='=' read -r key value; do
  key=$(echo "$key" | xargs)
  value=$(echo "$value" | xargs)

  case "$key" in
    "SLACK_BOT_TOKEN") SLACK_BOT_TOKEN="$value" ;;
    "SLACK_CHANNEL") SLACK_CHANNEL="$value" ;;
  esac
done < "$SECRET_FILE"

message=":hammer_and_wrench: Android build started on \`d.popkov/desktop/feat/merge_win\`
:mag_right: Analytics look on dev
:clock2: It will be ready approximately at 13:28"
post_message "${SLACK_BOT_TOKEN}" "${SLACK_CHANNEL}" "$message"