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
        for file in ${files}; do
            if [ ! -f "${file}" ]; then
                echo "File not found: ${file}"
                exit 1
            fi
            echo "Uploading file: ${file}"

            local upload_result=$(upload_file "${slack_token}" "${file}")
            echo "Upload result: ${upload_result}"

            local upload_url=$(echo "${upload_result}" | jq -r '.upload_url')
            local file_id=$(echo "${upload_result}" | jq -r '.file_id')

            if [ -z "${upload_url}" ] || [ -z "${file_id}" ]; then
                echo "Error: Failed to parse upload URL or file ID."
                exit 1
            fi

            echo "Posting file: ${file} to ${upload_url}"
            local post_result=$(post_file "${upload_url}" "${file}")
            echo "${post_result}"

            local file_name=$(basename "${file}")
            filelist+=$(printf '%s{"id":"%s","title":"%s"}' "${comma}" "${file_id}" "${file_name}")
            comma=","
        done

        echo "File list: ${filelist}"
        local complete_result=$(complete_upload "${slack_token}" "${channel_id}" "${initial_comment}" "${filelist}")
        echo "${complete_result}"

        echo "File upload completed"
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
    local file_path=$2

    local file_name=$(basename "${file_path}")
    local file_size=$(wc -c < "${file_path}" | sed 's/^[ \t]*//;s/[ \t]*$//')

    local command="curl -s \
      -F token=${slack_token} \
      -F length=${file_size} \
      -F filename=${file_name} \
      'https://slack.com/api/files.getUploadURLExternal'"
    local response=$(eval "${command}")

    if [ "$(echo "${response}" | jq -r '.ok')" != "true" ]; then
        echo "Failed to get upload url: ${response}"
        exit 1
    fi

    echo "${response}"
}

function post_file() {
    local upload_url=$1
    local file_path=$2
    local command="curl -s -X POST '${upload_url}' --data-binary @'${file_path}'"
    local response=$(eval "${command}")

    if [ "$(echo "${response}" | grep -c "OK")" -eq 0 ]; then
        echo "Failed to post file: ${response}"
        exit 1
    fi

    echo "${response}"
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
    local response=$(eval "${command}")

    if [ "$(echo "${response}" | jq -r '.ok')" != "true" ]; then
        echo "Failed to complete upload: ${response}"
        exit 1
    fi

    echo "${response}"
}

function post_message() {
    local slack_token=$1
    local channel_id=$2
    local initial_comment=$3

    # Construct JSON payload with jq to ensure proper escaping
    local json_payload=$(jq -n \
        --arg channel "$channel_id" \
        --arg text "$initial_comment" \
        '{channel: $channel, text: $text}')

    # Make the API call
    local response=$(curl -s -X POST \
        -H "Authorization: Bearer ${slack_token}" \
        -H "Content-Type: application/json; charset=UTF-8" \
        -d "$json_payload" \
        'https://slack.com/api/chat.postMessage')

    # First check if we got any response at all
    if [ -z "$response" ]; then
        echo "Error: Empty response from Slack API"
        exit 1
    fi

    # Try to parse the response normally first
    if echo "$response" | jq -e '.ok' >/dev/null 2>&1; then
        if [ "$(echo "$response" | jq -r '.ok')" = "true" ]; then
            echo "Successfully posted message:"
            echo "$response" | jq .
            return 0
        else
            echo "Failed to post message:"
            echo "$response" | jq .
            exit 1
        fi
    else
        # If normal parsing fails, try a more lenient approach
        echo "Warning: Standard JSON parsing failed, attempting fallback method..."
        if grep -q '"ok":true' <<< "$response"; then
            echo "Successfully posted message (fallback detection):"
            echo "$response"
            return 0
        else
            echo "Failed to post message (fallback detection):"
            echo "$response"
            exit 1
        fi
    fi
}