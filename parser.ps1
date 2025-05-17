param (
    [string]$AipFile,
    [string]$JarMapFile
)

if (-not (Test-Path $JarMapFile)) {
    Write-Error "JarMapFile not found: $JarMapFile"
    exit 1
}

$JarMap = Import-PowerShellDataFile -Path $JarMapFile

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

    foreach ($pattern in $JarMap.Keys) {
        $regex = $pattern -replace "\*", ".*"
        foreach ($row in $rows.Clone()) {
            $sourcePath = $row.SourcePath
            if ($sourcePath -match $regex) {
                $row.ParentNode.RemoveChild($row) | Out-Null
                Write-Host "[INFO] Removed old reference: $sourcePath" -ForegroundColor DarkGray
            }
        }
    }

    foreach ($row in $rows) {
        $sourcePath = $row.SourcePath
        foreach ($pattern in $JarMap.Keys) {
            $regex = $pattern -replace "\*", ".*"
            if ($sourcePath -match $regex) {
                $newJar = $JarMap[$pattern]
                $oldSourcePath = $row.SourcePath
                $row.SetAttribute("SourcePath", "..\\app\\$newJar")
                $row.SetAttribute("File", $newJar)
                $row.SetAttribute("FileName", "OUTPUT~1.JAR|$newJar")
                Write-Host "[DEBUG] Replaced SourcePath '$oldSourcePath' → '..\\app\\$newJar'" -ForegroundColor Yellow
                $replacementCount++
                break
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
