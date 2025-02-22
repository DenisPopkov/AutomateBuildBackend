$SECRET_FILE = "C:\Users\BlackBricks\Desktop\secret.txt"

if (!(Test-Path $SECRET_FILE)) {
    Write-Host "Error: secret.txt file not found at $SECRET_FILE"
    exit 1
}

$SLACK_BOT_TOKEN = ""
$SLACK_CHANNEL = ""

Get-Content $SECRET_FILE | ForEach-Object {
    $key, $value = $_ -split '=', 2
    $key = $key.Trim()
    $value = $value.Trim()
    
    switch ($key) {
        "SLACK_BOT_TOKEN" { $SLACK_BOT_TOKEN = $value }
        "SLACK_CHANNEL" { $SLACK_CHANNEL = $value }
    }
}

param (
    [string]$BRANCH_NAME,
    [bool]$BUMP_VERSION
)

if (-not $BRANCH_NAME) {
    Write-Host "Error: Branch name is required"
    exit 1
}

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

if ($BUMP_VERSION) {
    $VERSION_CODE = [int]$VERSION_CODE + 1
    (Get-Content $gradlePropsPath) -replace 'desktop\.build\.number\s*=\s*\d+', "desktop.build.number=$VERSION_CODE" | Set-Content $gradlePropsPath
} else {
    Write-Host "Nothing to bump"
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

$NEW_MSI_PATH = $FINAL_MSI_PATH -replace ' ', '_'
Move-Item -Path $FINAL_MSI_PATH -Destination $NEW_MSI_PATH
Write-Host "Renamed file: '$NEW_MSI_PATH'"
