#!/bin/bash

function execute_file_upload() {
    local slack_token=$1
    local channel_id=$2
    local initial_comment=$3
    local action=$4
    shift 4
    local files=$@

    if [ -z "${slack_token}" ]; then
        echo "slack_token is required"
        exit 1
    fi

    if [ -z "${channel_id}" ]; then
        echo "channel_id is required"
        exit 1
    fi

    if [ "${action}" == "upload" ]; then
        # Upload files to Slack
        for file in ${files}; do
            if [ ! -f "${file}" ]; then
                echo "File not found: ${file}"
                exit 1
            fi
            echo "Uploading file: ${file}"

            local upload_result=$(upload_file "${slack_token}" "${channel_id}" "${file}")
            echo "Upload result: ${upload_result}"

            local file_id=$(echo "${upload_result}" | jq -r '.file.id')

            if [ -z "${file_id}" ]; then
                echo "Error: Failed to upload file."
                exit 1
            fi

            echo "File uploaded successfully with ID: ${file_id}"
        done

        echo "File upload completed"

        # Optionally post a message
        post_message "${slack_token}" "${channel_id}" "${initial_comment}"

    elif [ "${action}" == "message" ]; then
        # Post a simple message without file upload
        post_message "${slack_token}" "${channel_id}" "${initial_comment}"

    else
        echo "Invalid action specified. Use 'upload' to upload files or 'message' to post a message."
        exit 1
    fi
}

function upload_file() {
    local slack_token=$1
    local channel_id=$2
    local file_path=$3

    local command="curl -s -X POST \
        -H \"Authorization: Bearer ${slack_token}\" \
        -F file=@${file_path} \
        -F channels=${channel_id} \
        -F initial_comment=\"Uploading new build: ${file_path}\" \
        'https://slack.com/api/files.upload'"

    local response=$(eval "${command}")

    if [ "$(echo "${response}" | jq -r '.ok')" != "true" ]; then
        echo "Failed to upload file: ${response}"
        exit 1
    fi

    echo "${response}"
}

function post_message() {
    local slack_token=$1
    local channel_id=$2
    local initial_comment=$3

    local command="curl -s -X POST \
        -H \"Authorization: Bearer ${slack_token}\" \
        -H \"Content-Type: application/json\" \
        -d '{
            \"channel\": \"${channel_id}\",
            \"text\": \"${initial_comment}\"
        }' \
        'https://slack.com/api/chat.postMessage'"

    local response=$(eval "${command}")

    if [ "$(echo "${response}" | jq -r '.ok')" != "true" ]; then
        echo "Failed to post message: ${response}"
        exit 1
    fi

    echo "Message posted successfully"
}
