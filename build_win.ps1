param(
    [string]$BRANCH_NAME,
    [string]$USE_DEV_ANALYTICS
)

$SECRET_FILE = "C:\Users\BlackBricks\Desktop\secret.txt"

Write-Host "Branch name '$BRANCH_NAME'"

$secrets = Get-Content $SECRET_FILE

foreach ($line in $secrets) {
    if ([string]::IsNullOrWhiteSpace($line) -or $line.StartsWith("#")) {
        continue
    }

    $splitLine = $line -split '=', 2

    if ($splitLine.Length -eq 2) {
        $key = $splitLine[0].Trim()
        $value = $splitLine[1].Trim()

        if ([string]::IsNullOrEmpty($value)) {
            Write-Host "Warning: Value for '$key' is empty or null"
            continue
        }

        switch ($key) {
            "SLACK_BOT_TOKEN" { $SLACK_BOT_TOKEN = $value }
            "SLACK_CHANNEL" { $SLACK_CHANNEL = $value }
            default { Write-Host "Warning: Unknown key '$key'" }
        }
    } else {
        Write-Host "Warning: Invalid line format '$line'"
    }
}

$PROJECT_DIR = "C:\Users\BlackBricks\StudioProjects\SA_Neuro_Multiplatform"

# For analytics
$SHARED_GRADLE_FILE = "$PROJECT_DIR\shared\build.gradle.kts"
$PROD_SHARED_GRADLE_FILE = "C:\Users\BlackBricks\Desktop\prod\build.gradle.kts"

Set-Location -Path $PROJECT_DIR -ErrorAction Stop

Write-Host "Checking out branch: $BRANCH_NAME"
git stash push -m "Pre-build stash"
git fetch
if (!(git checkout $BRANCH_NAME)) { exit 1 }
git pull origin $BRANCH_NAME --no-rebase

# Extract version code and version name from gradle.properties
$gradlePropsPath = "$PROJECT_DIR\gradle.properties"
$VERSION_CODE = (Select-String '^desktop\.build\.number\s*=\s*(\d+)' $gradlePropsPath).Matches.Groups[1].Value
$VERSION_NAME = (Select-String '^desktop\.version\s*=\s*(\d+\.\d+\.\d+)' $gradlePropsPath).Matches.Groups[1].Value

if (-not $VERSION_CODE -or -not $VERSION_NAME) {
    Write-Host "Error: Unable to extract versionCode or versionName from gradle.properties"
    exit 1
}

$VERSION_CODE = [int]$VERSION_CODE + 1
(Get-Content $gradlePropsPath) -replace 'desktop\.build\.number\s*=\s*\d+', "desktop.build.number=$VERSION_CODE" | Set-Content $gradlePropsPath
Start-Sleep -Seconds 5
git pull origin "$BRANCH_NAME" --no-rebase
git add .
git commit -m "Windows version bump to $VERSION_CODE"
git push origin "$BRANCH_NAME"

if ($USE_DEV_ANALYTICS -eq $false) {
    Write-Host "Replacing $SHARED_GRADLE_FILE with $PROD_SHARED_GRADLE_FILE"
    Remove-Item -Force $SHARED_GRADLE_FILE
    Copy-Item -Path $PROD_SHARED_GRADLE_FILE -Destination $SHARED_GRADLE_FILE

    Start-Process "C:\Program Files\Android\Android Studio\bin\studio64.exe"

    Start-Sleep -Seconds 5

    Add-Type -AssemblyName System.Windows.Forms
    [System.Windows.Forms.SendKeys]::SendWait("^+O")

    Start-Sleep -Seconds 80
} else {
    Write-Host "Nothing to change with analytics"
}

Start-Sleep -Seconds 5

$analyticsMessage = ""

if ($USE_DEV_ANALYTICS -eq $true) {
    $analyticsMessage = "dev"
} else {
    $analyticsMessage = "prod"
}

$endTime = [System.TimeZoneInfo]::ConvertTimeBySystemTimeZoneId((Get-Date).AddMinutes(15), "Omsk Standard Time")
$formattedTime = $endTime.ToString("HH:mm")
$message = @"
:hammer_and_wrench: Windows build started on `$BRANCH_NAME`
:mag_right: Analytics look on $analyticsMessage
:clock2: It will be ready approximately at $formattedTime Omsk Time
"@
Post-Message -SlackToken $SLACK_BOT_TOKEN -ChannelId $SLACK_CHANNEL -InitialComment $message

# Replace NeuroWindow.kt just before building the MSI
$NEURO_WINDOW_FILE_PATH = "$PROJECT_DIR\desktopApp\src\main\kotlin\presentation\neuro_window\NeuroWindow.kt"
$NEURO_WINDOW_DSP_FILE = "C:\Users\BlackBricks\Desktop\build_dsp\NeuroWindow.kt"
$NEURO_WINDOW_N0_DSP_FILE = "C:\Users\BlackBricks\Desktop\no_dsp\NeuroWindow.kt"

Remove-Item -Force $NEURO_WINDOW_FILE_PATH -ErrorAction Ignore
Copy-Item -Path $NEURO_WINDOW_N0_DSP_FILE -Destination $NEURO_WINDOW_FILE_PATH

Write-Host "Building..."
./gradlew packageReleaseMsi

# Restore original NeuroWindow.kt file
Remove-Item -Force $NEURO_WINDOW_FILE_PATH
Copy-Item -Path $NEURO_WINDOW_DSP_FILE -Destination $NEURO_WINDOW_FILE_PATH

# Path to the build output
$DESKTOP_BUILD_PATH = "$PROJECT_DIR\desktopApp\build\compose\binaries\main-release\msi"

# Original MSI path after build (before renaming)
$FINAL_MSI_PATH = "$DESKTOP_BUILD_PATH\Neuro Desktop-$VERSION_NAME.msi"
$NEW_MSI_PATH = "$DESKTOP_BUILD_PATH\Neuro_Desktop-$VERSION_NAME-$VERSION_CODE.msi"

# Check if the original file exists (before renaming)
if (Test-Path $FINAL_MSI_PATH) {
    # If the destination file already exists, we delete it to avoid conflicts
    if (Test-Path $NEW_MSI_PATH) {
        Remove-Item $NEW_MSI_PATH -Force
        Write-Host "Deleted existing file: $NEW_MSI_PATH"
    }

    # Rename the file (Move-Item also renames it)
    Move-Item -Path $FINAL_MSI_PATH -Destination $NEW_MSI_PATH
    Write-Host "Renamed file: '$NEW_MSI_PATH'"
} else {
    Write-Host "Error: Build file '$FINAL_MSI_PATH' not found."
    exit 1
}

Start-Sleep -Seconds 20

Execute-FileUpload -SlackToken $SLACK_BOT_TOKEN -ChannelId $SLACK_CHANNEL -InitialComment "Windows from $BRANCH_NAME" -Action "upload" -Files $NEW_MSI_PATH

git pull origin "$BRANCH_NAME"  --no-rebase
git stash push -m "Stashing build.gradle.kts" --keep-index -- "$SHARED_GRADLE_FILE"
git add .
git commit -m "Windows hardcoded lib updated"
git push origin "$BRANCH_NAME"
