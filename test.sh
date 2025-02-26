#!/bin/bash

open -a "Android Studio"

# Wait for Android Studio to launch
sleep 5

osascript -e '
tell application "System Events"
    tell process "Android Studio"
        keystroke "O" using {command down, shift down}
    end tell
end tell
'
