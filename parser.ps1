param (
    [string]$AipFile = "C:\Users\BlackBricks\Applications\Neuro installer\installer_win\Neuro Desktop 2.aip",
    [string]$AppDir = "C:\Users\BlackBricks\Applications\Neuro installer\app",
    [string]$NewJarName = "test.jar"
)

function Update-AipJarReferences {
    param (
        [string]$AipFile,
        [string]$AppDir,
        [string]$NewJarName
    )

    Write-Host "[INFO] Updating .jar file references in $AipFile from $AppDir" -ForegroundColor Cyan

    if (-not (Test-Path $AipFile)) {
        Write-Error "AIP file not found: $AipFile"
        return
    }

    if (-not (Test-Path $AppDir)) {
        Write-Error "App directory not found: $AppDir"
        return
    }

    # Создаем резервную копию
    $backupFile = "$AipFile.bak"
    Copy-Item -Path $AipFile -Destination $backupFile -Force
    Write-Host "[INFO] Created backup: $backupFile" -ForegroundColor DarkGray

    # Загружаем XML
    [xml]$xml = Get-Content $AipFile -Raw
    if (-not $xml) {
        Write-Error "Failed to parse AIP XML."
        return
    }
    Write-Host "[INFO] Original XML content is valid" -ForegroundColor Green

    # Префиксы для замены
    $prefixes = @("shared-jvm", "skiko-awt-runtime-windows-x64", "output")

    # Получаем все ROW узлы
    $rows = $xml.SelectNodes("//ROW")
    $foundAny = $false

    foreach ($row in $rows) {
        $sourcePath = $row.SourcePath
        foreach ($prefix in $prefixes) {
            if ($sourcePath -like "*$prefix*") {
                $foundAny = $true
                $oldSourcePath = $row.SourcePath
                $row.SetAttribute("SourcePath", "..\\app\\$NewJarName")
                $row.SetAttribute("File", $NewJarName)
                $row.SetAttribute("FileName", "OUTPUT~1.JAR|$NewJarName")
                Write-Host "[DEBUG] Replaced SourcePath '$oldSourcePath' with '..\\app\\$NewJarName' and updated File & FileName" -ForegroundColor Yellow
            }
        }
    }

    if (-not $foundAny) {
        Write-Host "[INFO] No matching entries found for prefixes: $($prefixes -join ', ')" -ForegroundColor DarkGray
    }

    # Сохраняем обновленный файл
    $xml.Save($AipFile)
    Write-Host "[SUCCESS] AIP file updated and saved." -ForegroundColor Green
}

Update-AipJarReferences -AipFile $AipFile -AppDir $AppDir -NewJarName $NewJarName
