param (
    [string]$AipFile = "C:\Users\BlackBricks\Applications\Neuro installer\installer_win\Neuro Desktop 2.aip",
    [hashtable]$JarMap = @{
        "output-*.jar" = "output-1.0.0-a6ee8738a338e7399f71acc454becf.jar";
        "shared-jvm-*.jar" = "shared-jvm-1.0.0-5df8204ba5ccd6b335aa24fa32fbf4fa.jar";
        "skiko-awt-runtime-windows-x64-*.jar" = "skiko-awt-runtime-windows-x64-0.8.4-be7bb93d693279a57df682b756f865.jar"
    }
)

function Update-AipJarReferences {
    param (
        [string]$AipFile,
        [hashtable]$JarMap
    )

    Write-Host "[INFO] Updating .jar file references in $AipFile..." -ForegroundColor Cyan

    if (-not (Test-Path $AipFile)) {
        Write-Error "AIP file not found: $AipFile"
        return
    }

    $backupFile = "$AipFile.bak"
    Copy-Item -Path $AipFile -Destination $backupFile -Force
    Write-Host "[INFO] Created backup: $backupFile" -ForegroundColor DarkGray

    [xml]$xml = Get-Content $AipFile -Raw
    if (-not $xml) {
        Write-Error "Failed to parse AIP XML."
        return
    }

    Write-Host "[INFO] Original XML content is valid" -ForegroundColor Green

    $rows = $xml.SelectNodes("//ROW")
    $replacementCount = 0

    foreach ($row in $rows) {
        $sourcePath = $row.SourcePath
        foreach ($pattern in $JarMap.Keys) {
            $regex = ($pattern -replace "\*", ".*")  # Преобразуем glob в regex
            if ($sourcePath -match $regex) {
                $newJar = $JarMap[$pattern]
                $oldSourcePath = $row.SourcePath
                $row.SetAttribute("SourcePath", "..\\app\\$newJar")
                $row.SetAttribute("File", $newJar)
                $row.SetAttribute("FileName", "OUTPUT~1.JAR|$newJar")
                Write-Host "[DEBUG] Replaced SourcePath '$oldSourcePath' → '..\\app\\$newJar'" -ForegroundColor Yellow
                $replacementCount++
                break  # не проверяем другие паттерны для этой строки
            }
        }
    }

    if ($replacementCount -eq 0) {
        Write-Host "[INFO] No .jar entries matched provided patterns." -ForegroundColor DarkGray
    } else {
        Write-Host "[SUCCESS] Updated $replacementCount .jar references." -ForegroundColor Green
    }

    $xml.Save($AipFile)
    Write-Host "[SUCCESS] AIP file updated and saved." -ForegroundColor Green
}

Update-AipJarReferences -AipFile $AipFile -JarMap $JarMap
