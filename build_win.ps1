$SECRET_FILE = "C:\Users\BlackBricks\Desktop\secret.txt"
$BRANCH_NAME = "build_win_soundcheck"
$BUMP_VERSION = "false"

# Check if the secret file exists
if (!(Test-Path $SECRET_FILE)) {
    Write-Host "Error: secret.txt file not found at $SECRET_FILE"
    exit 1
}

# Read secrets from the file
$secrets = Get-Content $SECRET_FILE

foreach ($line in $secrets) {
    # Ignore empty lines or lines starting with # (comment lines)
    if ([string]::IsNullOrWhiteSpace($line) -or $line.StartsWith("#")) {
        continue
    }

    # Split each line by '=' to get key-value pairs
    $splitLine = $line -split '=', 2

    # Check if the line has exactly two parts: key and value
    if ($splitLine.Length -eq 2) {
        $key = $splitLine[0].Trim()
        $value = $splitLine[1].Trim()

        # Check if the value is null or empty
        if ([string]::IsNullOrEmpty($value)) {
            Write-Host "Warning: Value for '$key' is empty or null"
            continue
        }

        # Assign values based on keys
        switch ($key) {
            "SLACK_BOT_TOKEN" { $SLACK_BOT_TOKEN = $value }
            "SLACK_CHANNEL" { $SLACK_CHANNEL = $value }
            default { Write-Host "Warning: Unknown key '$key'" }
        }
    } else {
        Write-Host "Warning: Invalid line format '$line'"
    }
}

# Output the values (for debugging purposes)
Write-Host "SLACK_BOT_TOKEN: $SLACK_BOT_TOKEN"
Write-Host "SLACK_CHANNEL: $SLACK_CHANNEL"

$PROJECT_DIR = "C:\Users\BlackBricks\StudioProjects\SA_Neuro_Multiplatform"
Set-Location -Path $PROJECT_DIR -ErrorAction Stop

Write-Host "Checking out branch: $BRANCH_NAME"
git fetch
if (!(git checkout $BRANCH_NAME)) { exit 1 }
git pull origin $BRANCH_NAME

# Extract version code and version name from gradle.properties
$gradlePropsPath = "$PROJECT_DIR\gradle.properties"
$VERSION_CODE = (Select-String '^desktop\.build\.number\s*=\s*(\d+)' $gradlePropsPath).Matches.Groups[1].Value
$VERSION_NAME = (Select-String '^desktop\.version\s*=\s*(\d+\.\d+\.\d+)' $gradlePropsPath).Matches.Groups[1].Value

if (-not $VERSION_CODE -or -not $VERSION_NAME) {
    Write-Host "Error: Unable to extract versionCode or versionName from gradle.properties"
    exit 1
}

# Bump version if required
if ($BUMP_VERSION -eq "true") {
    $VERSION_CODE = [int]$VERSION_CODE + 1
    (Get-Content $gradlePropsPath) -replace 'desktop\.build\.number\s*=\s*\d+', "desktop.build.number=$VERSION_CODE" | Set-Content $gradlePropsPath
} else {
    Write-Host "Nothing to bump"
}

# Paths for build files
$DESKTOP_BUILD_FILE = "$PROJECT_DIR\desktopApp\build.gradle.kts"
$DESKTOP_DSP_BUILD_FILE = "C:\Users\BlackBricks\Desktop\build_dsp\build.gradle.kts"
$DESKTOP_N0_DSP_BUILD_FILE = "C:\Users\BlackBricks\Desktop\no_dsp\build.gradle.kts"
$BUILD_PATH = "$PROJECT_DIR\desktopApp\build"
$SET_UPDATED_LIB_PATH = "$PROJECT_DIR\shared\src\commonMain\resources\MR\files\libdspmac.dylib"
$CACHE_UPDATED_LIB_PATH = "$PROJECT_DIR\desktopApp\build\native\libdspmac.dylib"

# Replace files for build
Remove-Item -Force $DESKTOP_N0_DSP_BUILD_FILE -ErrorAction Ignore
Copy-Item -Path $DESKTOP_BUILD_FILE -Destination $DESKTOP_N0_DSP_BUILD_FILE

Write-Host "Replacing $DESKTOP_BUILD_FILE with $DESKTOP_DSP_BUILD_FILE"
Remove-Item -Force $DESKTOP_BUILD_FILE -ErrorAction Ignore
Copy-Item -Path $DESKTOP_DSP_BUILD_FILE -Destination $DESKTOP_BUILD_FILE

Remove-Item -Recurse -Force $BUILD_PATH -ErrorAction Ignore
Copy-Item -Path $DESKTOP_DSP_BUILD_FILE -Destination $DESKTOP_BUILD_FILE

# Compile Kotlin
Set-Location -Path $PROJECT_DIR
./gradlew compileKotlin

# Restore original build file and lib
Remove-Item -Force $DESKTOP_BUILD_FILE
Copy-Item -Path $DESKTOP_N0_DSP_BUILD_FILE -Destination $DESKTOP_BUILD_FILE

Remove-Item -Force $SET_UPDATED_LIB_PATH
Copy-Item -Path $CACHE_UPDATED_LIB_PATH -Destination $SET_UPDATED_LIB_PATH

Write-Host "Building..."
./gradlew packageReleaseMsi

# MSI path and final file
$DESKTOP_BUILD_PATH = "$PROJECT_DIR\desktopApp\build\compose\binaries\main-release\msi"
$FINAL_MSI_PATH = "$DESKTOP_BUILD_PATH\Neuro_Desktop-$VERSION_NAME-$VERSION_CODE.msi"

if (!(Test-Path $FINAL_MSI_PATH)) {
    Write-Host "Error: Build not found at expected path: $FINAL_MSI_PATH"
    exit 1
}

Write-Host "Built successfully: $FINAL_MSI_PATH"

# Renaming MSI file with version code in square brackets
$NEW_MSI_PATH = $FINAL_MSI_PATH -replace ' ', '_'
$NEW_MSI_PATH = $NEW_MSI_PATH -replace "($VERSION_NAME)-($VERSION_CODE)\.msi", "$VERSION_NAME-[$VERSION_CODE].msi"

# Make sure the final MSI file is not being overwritten, and move it to the correct location
if ($FINAL_MSI_PATH -ne $NEW_MSI_PATH) {
    Move-Item -Path $FINAL_MSI_PATH -Destination $NEW_MSI_PATH
    Write-Host "Renamed file: '$NEW_MSI_PATH'"
} else {
    Write-Host "No renaming needed, file already named as: '$NEW_MSI_PATH'"
}

## Upload to Slack using the script
#Write-Host "Uploading renamed .msi to Slack..."
#execute_file_upload "${SLACK_BOT_TOKEN}" "${SLACK_CHANNEL}" "Windows MSI signed from $BRANCH_NAME" "upload" "${NEW_MSI_PATH}"
#
#if ($?) {
#    Write-Host "MSI sent to Slack successfully."
#    git add .
#    git commit -m "Update hardcoded libs"
#    git push origin $BRANCH_NAME
#} else {
#    Write-Host "Error committing hardcoded lib."
#    exit 1
#}
