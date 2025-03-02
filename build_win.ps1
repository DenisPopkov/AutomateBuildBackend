param(
    [string]$BRANCH_NAME,
    [string]$BUMP_VERSION,
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
$PROD_SHARED_GRADLE_FILE = "C:\Users\BlackBricks\Desktop\default\build.gradle.kts"

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

if ($BUMP_VERSION -eq "true") {
    $VERSION_CODE = [int]$VERSION_CODE + 1
    (Get-Content $gradlePropsPath) -replace 'desktop\.build\.number\s*=\s*\d+', "desktop.build.number=$VERSION_CODE" | Set-Content $gradlePropsPath
    Start-Sleep -Seconds 5
    git pull origin "$BRANCH_NAME" --no-rebase
    git add .
    git commit -m "Windows version bump to $VERSION_CODE"
    git push origin "$BRANCH_NAME"
} else {
    Write-Host "Nothing to bump"
}

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

function Execute-FileUpload {
    param (
        [string]$SlackToken,
        [string]$ChannelId,
        [string]$InitialComment,
        [string]$Action,
        [string[]]$Files
    )

    if (-not $SlackToken) {
        Write-Host "SlackToken is required"
        exit 1
    }

    if (-not $ChannelId) {
        Write-Host "ChannelId is required"
        exit 1
    }

    if ($Action -eq "upload") {
        $filelist = @()
        $comma = ""

        foreach ($file in $Files) {
            if (-not (Test-Path $file)) {
                Write-Host "File not found: $file"
                exit 1
            }
            Write-Host "Uploading file: $file"

            $uploadResult = Upload-File -SlackToken $SlackToken -FilePath $file
            Write-Host "Upload result: $uploadResult"

            $uploadUrl = $uploadResult.upload_url
            $fileId = $uploadResult.file_id

            if (-not $uploadUrl -or -not $fileId) {
                Write-Host "Error: Failed to parse upload URL or file ID."
                exit 1
            }

            Write-Host "Posting file: $file to $uploadUrl"
            $postResult = Post-File -UploadUrl $uploadUrl -FilePath $file
            Write-Host "$postResult"

            $fileName = [System.IO.Path]::GetFileName($file)
            $filelist += @{id = $fileId; title = $fileName}
        }

        Write-Host "File list: $($filelist | ConvertTo-Json)"
        $completeResult = Complete-Upload -SlackToken $SlackToken -ChannelId $ChannelId -InitialComment $InitialComment -FileId $fileId
        Write-Host "$completeResult"

        Write-Host "File upload completed"
    } elseif ($Action -eq "message") {
        Post-Message -SlackToken $SlackToken -ChannelId $ChannelId -InitialComment $InitialComment
    } else {
        Write-Host "Invalid action specified. Use 'upload' to upload files or 'message' to post a message."
        exit 1
    }
}

function Upload-File {
    param (
        [string]$SlackToken,
        [string]$FilePath
    )

    $fileName = [System.IO.Path]::GetFileName($FilePath)
    $fileSize = (Get-Item $FilePath).length

    $url = "https://slack.com/api/files.getUploadURLExternal"

    $headers = @{
        "Authorization" = "Bearer $SlackToken"
    }

    $body = @{
        "length"   = $fileSize
        "filename" = $fileName
    }

    try {
        $response = Invoke-WebRequest -Uri $url -Method Post -Headers $headers -Body $body -ContentType "application/x-www-form-urlencoded"
        $responseContent = $response.Content | ConvertFrom-Json

        if ($responseContent.ok -ne $true) {
            Write-Host "Failed to get upload URL: $($responseContent | ConvertTo-Json)"
            exit 1
        }

        return $responseContent
    } catch {
        Write-Host "Error during file upload: $_"
        exit 1
    }
}

function Post-File {
    param (
        [string]$UploadUrl,
        [string]$FilePath
    )

    if (-not (Test-Path -Path $FilePath)) {
        Write-Host "File not found: $FilePath"
        exit 1
    }

    $escapedFilePath = "`"$FilePath`""
    $escapedUploadUrl = "`"$UploadUrl`""

    $command = "curl -s -X POST $escapedUploadUrl --data-binary @$escapedFilePath"

    try {
        $process = Start-Process -FilePath "cmd.exe" -ArgumentList "/c $command" -PassThru -Wait

        if ($process.ExitCode -ne 0) {
            Write-Host "Error during file post. Exit code: $($process.ExitCode)"
            exit 1
        }

        Write-Host "File posted successfully"
    } catch {
        Write-Host "Error during file post: $_"
        exit 1
    }
}

function Complete-Upload {
    param(
        [string]$slackToken,
        [string]$channelId,
        [string]$initialComment,
        [string]$fileId
    )

    $url = "https://slack.com/api/files.completeUploadExternal"
    $headers = @{
        "Authorization" = "Bearer $slackToken"
        "Content-Type"  = "application/json; charset=utf-8"
    }

    $body = @{
        "files" = @(
            @{
                "id" = $fileId
            }
        )
        "initial_comment" = $initialComment
        "channel_id"      = $channelId
    } | ConvertTo-Json

    $response = Invoke-RestMethod -Uri $url -Method Post -Headers $headers -Body $body

    if ($response.ok -ne $true) {
        Write-Host "Failed to complete upload: $($response | ConvertTo-Json)"
        exit 1
    }

    return $response
}

function Post-Message {
    param (
        [string]$SlackToken,
        [string]$ChannelId,
        [string]$InitialComment
    )

    # Create the JSON body for the request
    $body = @{
        channel = $ChannelId
        text = $InitialComment
    } | ConvertTo-Json

    # Print the JSON body for debugging
    Write-Host "Request Body: $body"

    # Send the request to Slack API
    try {
        $response = Invoke-RestMethod -Uri 'https://slack.com/api/chat.postMessage' `
            -Method Post `
            -Headers @{
                "Authorization" = "Bearer $SlackToken"
                "Content-Type" = "application/json; charset=utf-8"
            } `
            -Body $body

        # Check if the request was successful
        if ($response.ok -ne $true) {
            Write-Host "Failed to post message: $($response | ConvertTo-Json)"
            exit 1
        }

        # Output the response
        Write-Host "Message posted successfully: $($response | ConvertTo-Json)"
    } catch {
        Write-Host "Error: Failed to send request to Slack API. Details: $_"
        exit 1
    }
}

Start-Sleep -Seconds 5

$endTime = [System.TimeZoneInfo]::ConvertTimeBySystemTimeZoneId((Get-Date).AddMinutes(15), "Omsk Standard Time")
$formattedTime = $endTime.ToString("HH:mm")
$message = "Windows build started. It will be ready approximately at $formattedTime Omsk Time."
Post-Message -SlackToken $SLACK_BOT_TOKEN -ChannelId $SLACK_CHANNEL -InitialComment $message

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
