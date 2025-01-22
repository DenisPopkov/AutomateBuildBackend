#!/bin/bash

SECRET_FILE="/Users/denispopkov/Desktop/secret.txt"

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
    "KEYFILE") KEYFILE="$value" ;;
    "STORE_PASSWORD") STORE_PASSWORD="$value" ;;
    "KEY_ALIAS") KEY_ALIAS="$value" ;;
    "KEY_PASSWORD") KEY_PASSWORD="$value" ;;
  esac
done < "$SECRET_FILE"

BRANCH_NAME=$1

if [ -z "$BRANCH_NAME" ]; then
  echo "Error: Branch name is required"
  exit 1
fi


function execute_file_upload() {
  local slack_token=$1
  local channel_id=$2
  local initial_comment=$3
  shift 3
  local files=$@

  if [ -z ${slack_token} ]; then
    echo "slack_token is required"
    exit 1
  fi

  if [ -z ${channel_id} ]; then
    echo "channel_id is required"
    exit 1
  fi

  for file in ${files}; do
    if [ ! -f ${file} ]; then
      echo "File not found: ${file}"
      exit 1
    fi
  done

  local filelist=""
  local comma=""
  for file in ${files}; do
    echo "Uploading file: ${file}"

    local upload_result=$(upload_file ${slack_token} ${file})
    echo "upload result: ${upload_result}"
    local upload_url=$(echo ${upload_result} | jq -r '.upload_url')
    local file_id=$(echo ${upload_result} | jq -r '.file_id')

    echo "Posting file: ${file} to ${upload_url}"
    local post_result=$(post_file ${upload_url} ${file})
    echo ${post_result}

    local file_name=$(basename ${file})
    filelist+=$(printf '%s{"id":"%s","title":"%s"}' "${comma}" "${file_id}" "${file_name}")

    comma=","
  done

  echo "filelist: ${filelist}"
  local complete_result=$(complete_upload "${slack_token}" "${channel_id}" "${initial_comment}" "${filelist}")
  echo ${complete_result}

  echo "File upload completed"
}

function upload_file() {
  local slack_token=$1
  local file_path=$2

  local file_name=$(basename ${file_path})
  local file_size=$(wc -c < ${file_path} | sed 's/^[ \t]*//;s/[ \t]*$//')

  local command="curl -s \
    -F token=${slack_token} \
    -F length=${file_size} \
    -F filename=${file_name} \
    'https://slack.com/api/files.getUploadURLExternal'"
  local response=$(eval ${command})

  if [ $(echo ${response} | jq -r '.ok') != "true" ]; then
    echo "Failed to get upload url: ${response}"
    exit 1
  fi

  echo ${response}
}

function post_file() {
  local upload_url=$1
  local file_path=$2
  local command="curl -s -X POST ${upload_url} --data-binary @${file_path}"
  local response=$(eval ${command})

  if [ $(echo ${response} | grep -c "OK") -eq 0 ]; then
    echo "Failed to post file: ${response}"
    exit 1
  fi

  echo ${response}
}

function complete_upload() {
  local slack_token=$1
  local channel_id=$2
  local initial_comment=$3
  local filelist=$4
  local command="curl -s -X POST \
    -H \"Authorization: Bearer ${slack_token}\" \
    -H \"Content-Type: application/json\" \
    -d '{
      \"files\": [${filelist}],
      \"initial_comment\": \"${initial_comment}\",
      \"channel_id\": \"${channel_id}\"
    }' \
    'https://slack.com/api/files.completeUploadExternal'"
  local response=$(eval ${command})

  if [ $(echo ${response} | jq -r '.ok') != "true" ]; then
    echo "Failed to complete upload: ${response}"
    exit 1
  fi

  echo ${response}
}

echo "Opening Android Studio..."
open -a "Android Studio"

PROJECT_DIR="/Users/denispopkov/AndroidStudioProjects/SA_Neuro_Multiplatform"
cd "$PROJECT_DIR" || { echo "Project directory not found!"; exit 1; }

echo "Checking out branch: $BRANCH_NAME"
git fetch && git checkout "$BRANCH_NAME" && git pull origin "$BRANCH_NAME"

# Build Signed APK
echo "Building signed APK..."
./gradlew assembleRelease \
  -Pandroid.injected.signing.store.file="$KEYFILE" \
  -Pandroid.injected.signing.store.password="$STORE_PASSWORD" \
  -Pandroid.injected.signing.key.alias="$KEY_ALIAS" \
  -Pandroid.injected.signing.key.password="$KEY_PASSWORD"

# Find the signed APK
APK_PATH="$PROJECT_DIR/androidApp/build/outputs/apk/release/androidApp-release.apk"

if [ ! -f "$APK_PATH" ]; then
  echo "Error: Signed APK not found at expected path: $APK_PATH"
  exit 1
fi

echo "APK built successfully: $APK_PATH"

# Slack Upload
FILE_PATH="$APK_PATH"

# Upload APK to Slack
echo "Uploading APK to Slack..."
execute_file_upload "${SLACK_BOT_TOKEN}" "${SLACK_CHANNEL}" "test" "${FILE_PATH}"

if [ $? -eq 0 ]; then
    echo "APK sent to Slack successfully."
else
    echo "Error sending APK to Slack."
    exit 1
fi
