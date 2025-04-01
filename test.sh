#!/bin/bash

echo "Opening Android Studio..."
"/c/Program Files/Android/Android Studio/bin/studio64.exe" &

cd "$PROJECT_DIR" || { echo "Project directory not found!"; exit 1; }

echo CreateObject("WScript.Shell").SendKeys "^(+O" > sendkeys.vbs & cscript //nologo sendkeys.vbs & del sendkeys.vbs