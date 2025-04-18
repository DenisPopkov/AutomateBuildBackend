#!/bin/bash

source "./slack_upload.sh"
SECRET_FILE="/Users/denispopkov/Desktop/secret.txt"

while IFS='=' read -r key value; do
  key=$(echo "$key" | xargs)
  value=$(echo "$value" | xargs)
  case "$key" in
    "SLACK_BOT_TOKEN") SLACK_BOT_TOKEN="$value" ;;
    "SLACK_CHANNEL") SLACK_CHANNEL="$value" ;;
  esac
done < "$SECRET_FILE"

# Отправляем первое сообщение и сохраняем ts
end_time=$(TZ=Asia/Omsk date -v+60M "+%H:%M")
message=":hammer_and_wrench: Test message for \`d.popkov/desktop/feat/lib_obsf\`
:mag_right: Analytics look on test
:clock2: It will be ready approximately at $end_time"
first_ts=$(post_message "${SLACK_BOT_TOKEN}" "${SLACK_CHANNEL}" "$message")
echo "Первое сообщение отправлено с ts: $first_ts"
#
## Отправляем второе сообщение
#second_ts=$(post_message "${SLACK_BOT_TOKEN}" "${SLACK_CHANNEL}" "Второе сообщение")
#echo "Второе сообщение отправлено с ts: $second_ts"
#
## Удаляем первое сообщение
#delete_message "${SLACK_BOT_TOKEN}" "${SLACK_CHANNEL}" "$first_ts"
