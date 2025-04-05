#!/bin/bash

source "./slack_upload.sh"
source "./utils.sh"

BRANCH_NAME=$1
isUseDevAnalytics=$2

git pull origin "$BRANCH_NAME" --no-rebase
git commit -m "build: windows isUseDevAnalytics=${isUseDevAnalytics}"
git push origin "$BRANCH_NAME"

#if [ "$isUseDevAnalytics" == "false" ]; then
#  enable_prod_keys
#
#  sleep 5
#
#  powershell.exe -command "[System.Windows.Forms.SendKeys]::SendWait('^+O')"
#
#  sleep 80
#else
#  echo "Nothing to change with analytics"
#fi
#
