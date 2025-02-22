$SECRET_FILE = "C:\Users\BlackBricks\Desktop\secret.txt"
$BRANCH_NAME = "build_win_soundcheck"
$BUMP_VERSION = "false"

#param(
#    [string]$BRANCH_NAME,
#    [string]$BUMP_VERSION
#)

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
$CACHE_UPDATED_LIB_PATH = "$PROJECT_DIR\shared\build\resources\MR\files\libdspmac.dylib"

Remove-Item -Force $DESKTOP_N0_DSP_BUILD_FILE -ErrorAction Ignore
Copy-Item -Path $DESKTOP_BUILD_FILE -Destination $DESKTOP_N0_DSP_BUILD_FILE

Write-Host "Replacing $DESKTOP_BUILD_FILE with $DESKTOP_DSP_BUILD_FILE"
Remove-Item -Force $DESKTOP_BUILD_FILE -ErrorAction Ignore
Copy-Item -Path $DESKTOP_DSP_BUILD_FILE -Destination $DESKTOP_BUILD_FILE

Remove-Item -Recurse -Force $BUILD_PATH -ErrorAction Ignore
Copy-Item -Path $DESKTOP_DSP_BUILD_FILE -Destination $DESKTOP_BUILD_FILE

# Replace NeuroWindow.kt just before building the MSI
$NEURO_WINDOW_FILE_PATH = "$PROJECT_DIR\desktopApp\src\main\kotlin\presentation\neuro_window\NeuroWindow.kt"
$NEURO_WINDOW_DSP_FILE = "C:\Users\BlackBricks\Desktop\build_dsp\NeuroWindow.kt"
$NEURO_WINDOW_N0_DSP_FILE = "C:\Users\BlackBricks\Desktop\no_dsp\NeuroWindow.kt"

Remove-Item -Force $NEURO_WINDOW_FILE_PATH -ErrorAction Ignore
Copy-Item -Path $NEURO_WINDOW_N0_DSP_FILE -Destination $NEURO_WINDOW_FILE_PATH

# Compile Kotlin
Set-Location -Path $PROJECT_DIR
./gradlew compileKotlin

Write-Host "Building..."
./gradlew packageReleaseMsi

# Restore original NeuroWindow.kt file
Remove-Item -Force $NEURO_WINDOW_FILE_PATH
Copy-Item -Path $NEURO_WINDOW_DSP_FILE -Destination $NEURO_WINDOW_FILE_PATH

# Restore original build file and lib
Remove-Item -Force $DESKTOP_BUILD_FILE
Copy-Item -Path $DESKTOP_N0_DSP_BUILD_FILE -Destination $DESKTOP_BUILD_FILE

Remove-Item -Force $SET_UPDATED_LIB_PATH
Copy-Item -Path $CACHE_UPDATED_LIB_PATH -Destination $SET_UPDATED_LIB_PATH

# Path to the build output
$DESKTOP_BUILD_PATH = "$PROJECT_DIR\desktopApp\build\compose\binaries\main-release\msi"

# Original MSI path after build (before renaming)
$FINAL_MSI_PATH = "$DESKTOP_BUILD_PATH\Neuro Desktop-$VERSION_NAME.msi"

# Construct the new MSI path with version code in square brackets
$NEW_MSI_PATH = "$DESKTOP_BUILD_PATH\Neuro_Desktop-$VERSION_NAME-[$VERSION_CODE].msi"

# Check if the original file exists (before renaming)
if (Test-Path $FINAL_MSI_PATH) {
    # If the destination file already exists, we delete it to avoid conflicts
    if (Test-Path $NEW_MSI_PATH) {
        Remove-Item $NEW_MSI_PATH -Force
        Write-Host "Deleted existing file: $NEW_MSI_PATH"
    }

    # Rename the file (Move-Item also renames it)
    Move-Item -Path $FINAL_MSI_PATH -Destination $NEW_MSI_PATH

    # Confirm the renaming
    Write-Host "Renamed file: '$NEW_MSI_PATH'"
} else {
    Write-Host "Error: Build file '$FINAL_MSI_PATH' not found."
    exit 1
}

function Execute-FileUpload {
    param (
        [string]$slackToken,
        [string]$channelId,
        [string]$initialComment,
        [string]$action,
        [string[]]$files
    )

    if (-not $slackToken) {
        Write-Host "slackToken is required"
        exit 1
    }

    if (-not $channelId) {
        Write-Host "channelId is required"
        exit 1
    }

    if ($action -eq "upload") {
        # Handle file upload
        $fileList = @()
        $comma = ""

        foreach ($file in $files) {
            Write-Host "Uploading file: $file"

            $uploadResult = Upload-File -slackToken $slackToken -filePath $file
            Write-Host "Upload result: $uploadResult"

            $uploadUrl = ($uploadResult | ConvertFrom-Json).upload_url
            $fileId = ($uploadResult | ConvertFrom-Json).file_id

            if (-not $uploadUrl -or -not $fileId) {
                Write-Host "Error: Failed to parse upload URL or file ID."
                exit 1
            }

            Write-Host "Posting file: $file to $uploadUrl"
            $postResult = Post-File -uploadUrl $uploadUrl -filePath $file
            Write-Host "$postResult"

            $fileName = [System.IO.Path]::GetFileName($file)
            $fileList += "{`"id`":`"$fileId`",`"title`":`"$fileName`"}"
        }

        Write-Host "File list: $fileList"
        $completeResult = Complete-Upload -slackToken $slackToken -channelId $channelId -initialComment $initialComment -fileList $fileList
        Write-Host "$completeResult"

        Write-Host "File upload completed"
    } elseif ($action -eq "message") {
        # Post a simple message without file upload
        Post-Message -slackToken $slackToken -channelId $channelId -initialComment $initialComment
    } else {
        Write-Host "Invalid action specified. Use 'upload' to upload files or 'message' to post a message."
        exit 1
    }
}

function Upload-File {
    param (
        [string]$slackToken,
        [string]$filePath
    )

    $fileName = [System.IO.Path]::GetFileName($filePath)

    # Calculate the file size using FileInfo
    $fileInfo = New-Object System.IO.FileInfo($filePath)
    $fileSize = $fileInfo.Length

    $uri = "https://slack.com/api/files.getUploadURLExternal"
    $headers = @{
        "Authorization" = "Bearer $slackToken"
    }

    $body = @{
        "length" = $fileSize
        "filename" = $fileName
        "token" = $slackToken
    }

    $response = Invoke-RestMethod -Uri $uri -Method Post -Headers $headers -Body $body -ContentType "application/x-www-form-urlencoded"

    if ($response.ok -ne $true) {
        Write-Host "Failed to get upload URL: $response"
        exit 1
    }

    return $response
}

function Post-File {
    param (
        [string]$uploadUrl,
        [string]$filePath
    )

    $response = Invoke-RestMethod -Uri $uploadUrl -Method Post -InFile $filePath -ContentType "application/octet-stream"

    if ($response -notcontains "OK") {
        Write-Host "Failed to post file: $response"
        exit 1
    }

    return $response
}

function Complete-Upload {
    param (
        [string]$slackToken,
        [string]$channelId,
        [string]$initialComment,
        [string[]]$fileList
    )

    $uri = "https://slack.com/api/files.completeUploadExternal"
    $headers = @{
        "Authorization" = "Bearer $slackToken"
        "Content-Type" = "application/json"
    }

    $body = @{
        "files" = $fileList
        "initial_comment" = $initialComment
        "channel_id" = $channelId
    } | ConvertTo-Json

    $response = Invoke-RestMethod -Uri $uri -Method Post -Headers $headers -Body $body

    if ($response.ok -ne $true) {
        Write-Host "Failed to complete upload: $response"
        exit 1
    }

    return $response
}

function Post-Message {
    param (
        [string]$slackToken,
        [string]$channelId,
        [string]$initialComment
    )

    $uri = "https://slack.com/api/chat.postMessage"
    $headers = @{
        "Authorization" = "Bearer $slackToken"
        "Content-Type" = "application/json"
    }

    $body = @{
        "channel" = $channelId
        "text" = $initialComment
    } | ConvertTo-Json

    $response = Invoke-RestMethod -Uri $uri -Method Post -Headers $headers -Body $body

    if ($response.ok -ne $true) {
        Write-Host "Failed to post message: $response"
        exit 1
    }

    return $response
}

Execute-FileUpload -slackToken $SLACK_BOT_TOKEN -channelId $SLACK_CHANNEL -initialComment "Windows from $BRANCH_NAME" -action "upload" -files $NEW_MSI_PATH

if ($?) {
    Write-Host "MSI sent to Slack successfully."
    git add .
    git commit -m "Update hardcoded libs"
    git push origin $BRANCH_NAME
} else {
    Write-Host "Error committing hardcoded lib."
    exit 1
}
