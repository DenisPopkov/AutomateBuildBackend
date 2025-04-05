#!/bin/bash

source "./slack_upload.sh"
source "./utils.sh"

BRANCH_NAME=$1

git pull origin "$BRANCH_NAME" --no-rebase
git commit -m "build: windows"
git push origin "$BRANCH_NAME"
