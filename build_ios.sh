#!/bin/bash

cd /Users/denispopkov/AndroidStudioProjects/SA_Neuro_Multiplatform/iosApp || exit

git fetch && git checkout "soundcheck_develop" && git pull origin "soundcheck_develop" || exit
git checkout "sc_fastlane" || exit
git merge "soundcheck_develop" || exit
fastlane testflight_upload