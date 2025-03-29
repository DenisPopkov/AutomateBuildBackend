#!/bin/bash

FILE="/Users/denispopkov/AndroidStudioProjects/SA_Neuro_Multiplatform/desktopApp/build.gradle.kts"

disable_dsp_gradle_task() {
sed -i '' -e '/tasks.named("compileKotlin") {/ {
    N
    N
    s/^/\/\*\
/
    s/$/\
\*\//
}' "$FILE"
}

enable_dsp_gradle_task() {
  sed -i '' -e '/\/\*$/,/\*\// {
    /\/\*/ {
        s/\/\*//
        N
    }
    /\*\// {
        s/\*\///
        N
    }
    s/\n//g
  }' "$FILE"
  echo "Block uncommented"
}
