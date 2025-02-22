$SECRET_FILE = "C:\Users\BlackBricks\Desktop\secret.txt"
$BRANCH_NAME = "build_win_soundcheck"
$BUMP_VERSION = "false"

if (!(Test-Path $SECRET_FILE)) {
    Write-Host "Error: secret.txt file not found at $SECRET_FILE"
    exit 1
}

# Read Slack credentials from secret.txt
$secrets = @{}
Get-Content $SECRET_FILE | ForEach-Object {
    $key, $value = $_ -split '='
    $key = $key.Trim()
    $value = $value.Trim()
    $secrets[$key] = $value
}

if (-not $secrets["SLACK_BOT_TOKEN"] -or -not $secrets["SLACK_CHANNEL"]) {
    Write-Host "Error: Missing Slack credentials in secret.txt"
    exit 1
}

$SLACK_BOT_TOKEN = $secrets["SLACK_BOT_TOKEN"]
$SLACK_CHANNEL = $secrets["SLACK_CHANNEL"]

$PROJECT_DIR = "C:\Users\BlackBricks\StudioProjects\SA_Neuro_Multiplatform"
Set-Location -Path $PROJECT_DIR -ErrorAction Stop

Write-Host "Checking out branch: $BRANCH_NAME"
git fetch
if (!(git checkout $BRANCH_NAME)) { exit 1 }
git pull origin $BRANCH_NAME

$gradlePropsPath = "$PROJECT_DIR\gradle.properties"
$VERSION_CODE = (Select-String '^desktop\.build\.number\s*=\s*(\d+)' $gradlePropsPath).Matches.Groups[1].Value
$VERSION_NAME = (Select-String '^desktop\.version\s*=\s*(\d+\.\d+\.\d+)' $gradlePropsPath).Matches.Groups[1].Value

if (-not $VERSION_CODE -or -not $VERSION_NAME) {
    Write-Host "Error: Unable to extract versionCode or versionName from gradle.properties"
    exit 1
}

if ($BUMP_VERSION -eq "true") {
    $VERSION_CODE = [int]$VERSION_CODE + 1
    (Get-Content $gradlePropsPath) -replace 'desktop\.build\.number\s*=\s*\d+', "desktop.build.number=$VERSION_CODE" | Set-Content $gradlePropsPath
} else {
    Write-Host "Version bump skipped (BUMP_VERSION is false)"
}

$DESKTOP_BUILD_FILE = "$PROJECT_DIR\desktopApp\build.gradle.kts"
$DESKTOP_DSP_BUILD_FILE = "C:\Users\BlackBricks\Desktop\build_dsp\build.gradle.kts"
$DESKTOP_N0_DSP_BUILD_FILE = "C:\Users\BlackBricks\Desktop\no_dsp\build.gradle.kts"
$BUILD_PATH = "$PROJECT_DIR\desktopApp\build"
$SET_UPDATED_LIB_PATH = "$PROJECT_DIR\shared\src\commonMain\resources\MR\files\libdspmac.dylib"
$CACHE_UPDATED_LIB_PATH = "$PROJECT_DIR\desktopApp\build\native\libdspmac.dylib"

Remove-Item -Force $DESKTOP_N0_DSP_BUILD_FILE -ErrorAction Ignore
Copy-Item -Path $DESKTOP_BUILD_FILE -Destination $DESKTOP_N0_DSP_BUILD_FILE

Write-Host "Replacing $DESKTOP_BUILD_FILE with $DESKTOP_DSP_BUILD_FILE"
Remove-Item -Force $DESKTOP_BUILD_FILE -ErrorAction Ignore
Copy-Item -Path $DESKTOP_DSP_BUILD_FILE -Destination $DESKTOP_BUILD_FILE

Remove-Item -Recurse -Force $BUILD_PATH -ErrorAction Ignore
Copy-Item -Path $DESKTOP_DSP_BUILD_FILE -Destination $DESKTOP_BUILD_FILE

Set-Location -Path $PROJECT_DIR
./gradlew compileKotlin

Remove-Item -Force $DESKTOP_BUILD_FILE
Copy-Item -Path $DESKTOP_N0_DSP_BUILD_FILE -Destination $DESKTOP_BUILD_FILE

Remove-Item -Force $SET_UPDATED_LIB_PATH
Copy-Item -Path $CACHE_UPDATED_LIB_PATH -Destination $SET_UPDATED_LIB_PATH

Write-Host "Building..."
./gradlew packageReleaseMsi

$DESKTOP_BUILD_PATH = "$PROJECT_DIR\desktopApp\build\compose\binaries\main-release\msi"
$FINAL_MSI_PATH = "$DESKTOP_BUILD_PATH\Neuro_Desktop-$VERSION_NAME-$VERSION_CODE.msi"

if (!(Test-Path $FINAL_MSI_PATH)) {
    Write-Host "Error: Build not found at expected path: $FINAL_MSI_PATH"
    exit 1
}

Write-Host "Built successfully: $FINAL_MSI_PATH"

# Rename the file with version code in brackets
$NEW_MSI_PATH = $FINAL_MSI_PATH -replace ' ', '_'
$NEW_MSI_PATH = $NEW_MSI_PATH -replace "$VERSION_CODE", "[$VERSION_CODE]"
Move-Item -Path $FINAL_MSI_PATH -Destination $NEW_MSI_PATH
Write-Host "Renamed file: '$NEW_MSI_PATH'"

# Upload MSI to Slack using external bash script
$slackUploadScript = "C:\Users\BlackBricks\PycharmProjects\AutomateBuildBackend\slack_upload.sh"

if (Test-Path $slackUploadScript) {
    Write-Host "Running Slack upload script..."
    $uploadCommand = "bash -c ""source '$slackUploadScript'; execute_file_upload '$SLACK_BOT_TOKEN' '$SLACK_CHANNEL' 'Windows MSI signed from $BRANCH_NAME' 'upload' '$NEW_MSI_PATH'"""
    Invoke-Expression $uploadCommand
} else {
    Write-Host "Error: Slack upload script not found at $slackUploadScript"
    exit 1
}

Write-Host "Process completed."
