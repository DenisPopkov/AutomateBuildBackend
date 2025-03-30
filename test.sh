#!/bin/bash

source "./slack_upload.sh"
source "./utils.sh"
SECRET_FILE="/c/Users/BlackBricks/Desktop/secret.txt"

while IFS='=' read -r key value; do
  key=$(echo "$key" | xargs)
  value=$(echo "$value" | xargs)

  case "$key" in
    "SLACK_BOT_TOKEN") SLACK_BOT_TOKEN="$value" ;;
    "SLACK_CHANNEL") SLACK_CHANNEL="$value" ;;
  esac
done < "$SECRET_FILE"

echo "[at - $SLACK_BOT_TOKEN. $SLACK_CHANNEL"

message=":hammer_and_wrench: Test msg \`d.popkov/desktop/feat/merge_win\`
:mag_right: Analytics look on dev
:clock2: It will be ready approximately at 13:28"
post_message "${SLACK_BOT_TOKEN}" "${SLACK_CHANNEL}" "$message"