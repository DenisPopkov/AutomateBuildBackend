#!/bin/bash

BRANCH_NAME=$1
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

WORKFLOW_FILENAME="build_windows.yml"

echo "Triggering GitHub Actions workflow '$WORKFLOW_FILENAME' on branch '$BRANCH_NAME'..."

curl -X POST \
  -H "Authorization: Bearer $GITHUB_TOKEN" \
  -H "Accept: application/vnd.github+json" \
  https://api.github.com/repos/"$REPO_OWNER"/"$REPO_NAME"/actions/workflows/$WORKFLOW_FILENAME/dispatches \
  -d "{\"ref\":\"$BRANCH_NAME\"}" \
  || echo "❌ Failed to trigger workflow" >> "$ERROR_LOG_FILE"
