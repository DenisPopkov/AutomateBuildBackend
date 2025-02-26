#!/bin/bash

end_time=$(TZ=Asia/Omsk date -v+15M "+%H:%M")
message="Android build started. It will be ready approximately at $end_time Omsk Time."
echo "$message"