#!/bin/bash

echo "Opening Android Studio..."
"/c/Program Files/Android/Android Studio/bin/studio64.exe" &

# Wait for Android Studio to open
sleep 5

cd "$PROJECT_DIR" || { echo "Project directory not found!"; exit 1; }

# Use PowerShell to send Ctrl+Shift+O
powershell -command "\
Add-Type -AssemblyName System.Windows.Forms; \
[System.Windows.Forms.SendKeys]::SendWait('^(+o)'); \
Start-Sleep -Milliseconds 100"