#!/bin/bash

osascript <<EOF
tell application "System Events"
  if exists application process "Android Studio" then
    set frontmost of application process "Android Studio" to true
    keystroke "q" using {command down}
    delay 0.5
    keystroke return
  else
    error "Error: Could not find the process for Android Studio. Verify the application name."
  end if
end tell
EOF
