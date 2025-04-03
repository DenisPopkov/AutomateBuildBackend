#!/bin/bash

PROJECT_DIR="/c/Users/BlackBricks/StudioProjects/SA_Neuro_Multiplatform"
FILE="$PROJECT_DIR/desktopApp/build.gradle.kts"
SHARED_GRADLE="$PROJECT_DIR/shared/build.gradle.kts"
ANDROID_GRADLE="$PROJECT_DIR/androidApp/build.gradle.kts"
SECRET_FILE="/c/Users/BlackBricks/Desktop/secret.txt"

while IFS='=' read -r key value; do
  key=$(echo "$key" | xargs)
  value=$(echo "$value" | xargs)

  case "$key" in
    "PROD_DESKTOP_KEY") PROD_DESKTOP_KEY="$value" ;;
    "PROD_MOBILE_KEY") PROD_MOBILE_KEY="$value" ;;
    "DEV_DESKTOP_KEY") DEV_DESKTOP_KEY="$value" ;;
    "DEV_MOBILE_KEY") DEV_MOBILE_KEY="$value" ;;
  esac
done < "$SECRET_FILE"

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

enable_prod_keys() {
    sed -i '' -e "/name = \"MIXPANEL_API_KEY_WINDOWS\"/,/const = true/s/$DEV_DESKTOP_KEY/$PROD_DESKTOP_KEY/g" "$SHARED_GRADLE"
    sed -i '' -e "/name = \"MIXPANEL_API_KEY_MACOS\"/,/const = true/s/$DEV_DESKTOP_KEY/$PROD_DESKTOP_KEY/g" "$SHARED_GRADLE"
    sed -i '' -e "/name = \"MIXPANEL_API_KEY_IOS\"/,/const = true/s/$DEV_MOBILE_KEY/$PROD_MOBILE_KEY/g" "$SHARED_GRADLE"
    sed -i '' -e "/name = \"MIXPANEL_API_KEY_ANDROID\"/,/const = true/s/$DEV_MOBILE_KEY/$PROD_MOBILE_KEY/g" "$SHARED_GRADLE"
    echo "Production API keys updated."
}

undo_enable_prod_keys() {
    sed -i '' -e "/name = \"MIXPANEL_API_KEY_WINDOWS\"/,/const = true/s/$PROD_DESKTOP_KEY/$DEV_DESKTOP_KEY/g" "$SHARED_GRADLE"
    sed -i '' -e "/name = \"MIXPANEL_API_KEY_MACOS\"/,/const = true/s/$PROD_DESKTOP_KEY/$DEV_DESKTOP_KEY/g" "$SHARED_GRADLE"
    sed -i '' -e "/name = \"MIXPANEL_API_KEY_IOS\"/,/const = true/s/$PROD_MOBILE_KEY/$DEV_MOBILE_KEY/g" "$SHARED_GRADLE"
    sed -i '' -e "/name = \"MIXPANEL_API_KEY_ANDROID\"/,/const = true/s/$PROD_MOBILE_KEY/$DEV_MOBILE_KEY/g" "$SHARED_GRADLE"
    echo "Production API keys reverted to dev."
}

uncomment_android_dsp_gradle_task() {
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
  }' "$ANDROID_GRADLE"
  echo "Block uncommented"
}

comment_android_dsp_gradle_task() {
  sed -i '' -e '/ndk {/ {
      N
      N
      s/^/\/\*\
/
      s/$/\
\*\//
  }' "$ANDROID_GRADLE"

  sed -i '' -e '/externalNativeBuild {/ {
      N
      N
      N
      N
      N
      s/^/\/\*\
/
      s/$/\
\*\//
  }' "$ANDROID_GRADLE"

  echo "Android DSP Gradle tasks commented"
}
