# Путь к файлам
$aipFile = "C:\Users\BlackBricks\Applications\Neuro installer\installer_win\Neuro Desktop 2.aip"
$appDir = "C:\Users\BlackBricks\Applications\Neuro installer\app"

if (-not (Test-Path -Path $aipFile -PathType Leaf)) {
    Write-Error "[ERROR] AIP file not found: $aipFile"
    exit 1
}

if (-not (Test-Path -Path $appDir -PathType Container)) {
    Write-Error "[ERROR] App directory not found: $appDir"
    exit 1
}

function Update-AipJarReferences {
    param (
        [string]$AipFile,
        [string]$AppDir
    )

    Write-Host "[INFO] Updating .jar file references in $AipFile from $AppDir"

    # Создаём резервную копию файла
    $backupFile = "$AipFile.bak"
    Copy-Item -Path $AipFile -Destination $backupFile -Force
    Write-Host "[INFO] Created backup: $backupFile"

    # Считаем весь файл в память
    $content = Get-Content -Path $AipFile -Raw -Encoding UTF8

    # Проверяем исходную валидность XML
    try {
        $xml = [xml]$content
        Write-Host "[INFO] Original XML content is valid"
    }
    catch {
        Write-Error "[ERROR] Original XML is invalid: $_"
        exit 1
    }

    # Список префиксов для целевых файлов
    $prefixes = @("shared-jvm", "skiko-awt-runtime-windows-x64", "output")

    foreach ($prefix in $prefixes) {
        # Экранируем префикс для regex
        $escapedPrefix = [regex]::Escape($prefix)
        # Паттерн для поиска строки
        $pattern = "<ROW File=`"[^`"]+`" Component_=`"([^`"]+)`" FileName=`"([^`"]+)`" Attributes=`"([^`"]+)`" SourcePath=`"\.\.\\app\\$escapedPrefix-[^`"]+\.jar`" SelfReg=`"([^`"]+)`"/>"

        # Отладочный вывод для проверки
        Write-Host "[DEBUG] Searching for pattern: $pattern"

        # Заменяем атрибут File на тестовое имя
        $newContent = $content -replace $pattern, {
            param($match)
            $component = $match.Groups[1].Value
            $fileName = $match.Groups[2].Value
            $attributes = $match.Groups[3].Value
            $sourcePath = $match.Groups[0].Value -replace ".*SourcePath=`"\.\.\\app\\([^`"]+)`".*", '$1'
            $selfReg = $match.Groups[4].Value

            # Экранируем специальные символы для XML
            $component = $component -replace '&', '&' -replace '<', '<' -replace '>', '>' -replace '"', '"' -replace "'", '''
            $fileName = $fileName -replace '&', '&' -replace '<', '<' -replace '>', '>' -replace '"', '"' -replace "'", '''
            $attributes = $attributes -replace '&', '&' -replace '<', '<' -replace '>', '>' -replace '"', '"' -replace "'", '''
            $sourcePath = $sourcePath -replace '&', '&' -replace '<', '<' -replace '>', '>' -replace '"', '"' -replace "'", '''
            $selfReg = $selfReg -replace '&', '&' -replace '<', '<' -replace '>', '>' -replace '"', '"' -replace "'", '''

            # Формируем строку замены
            $replacement = "<ROW File=`"test-hash.jar`" Component_=`"$component`" FileName=`"$fileName`" Attributes=`"$attributes`" SourcePath=`"..\\app\\$sourcePath`" SelfReg=`"$selfReg`"/>"

            # Проверяем валидность строки замены
            try {
                $testXml = "<root>$replacement</root>"
                [xml]$testXml | Out-Null
                Write-Host "[DEBUG] Replacement string for ${prefix} is valid XML"
            }
            catch {
                Write-Warning "[WARNING] Replacement string for ${prefix} is invalid XML: $_"
                Write-Host "[DEBUG] Invalid replacement: $replacement"
                return $match.Value # Не заменяем, оставляем оригинал
            }

            # Отладочный вывод
            Write-Host "[DEBUG] Original line: $($match.Value)"
            Write-Host "[DEBUG] Replacement string for ${prefix}: $replacement"
            Write-Host "[INFO] Found match for $prefix, SourcePath: $sourcePath"

            $replacement
        }

        # Если замена произошла, обновляем контент
        if ($newContent -ne $content) {
            Write-Host "[INFO] Updated reference for $prefix to test-hash.jar"
            $content = $newContent
        }
        else {
            Write-Warning "[WARNING] No match found for $prefix"
            Write-Host "[DEBUG] Checking for any $prefix in file..."
            $matches = [regex]::Matches($content, "<ROW[^>]+SourcePath=`"\.\.\\app\\$escapedPrefix-[^`"]+\.jar`"[^>]*>")
            if ($matches.Count -gt 0) {
                Write-Host "[DEBUG] Found $($matches.Count) line(s) with $prefix in SourcePath:"
                foreach ($m in $matches) {
                    Write-Host "[DEBUG] Line: $($m.Value)"
                }
            }
            else {
                Write-Host "[DEBUG] Prefix $prefix not found in any SourcePath."
            }
        }
    }

    # Проверяем валидность XML после изменений
    try {
        $xml = [xml]$content
        Write-Host "[INFO] Modified XML content is valid"
    }
    catch {
        Write-Error "[ERROR] Invalid XML after changes: $_"
        Write-Host "[INFO] Restoring from backup: $backupFile"
        Copy-Item -Path $backupFile -Destination $AipFile -Force
        exit 1
    }

    # Записываем обратно в файл
    Set-Content -Path $AipFile -Value $content -Encoding UTF8
    Write-Host "[INFO] Changes saved to $AipFile"
}

Update-AipJarReferences -AipFile $aipFile -AppDir $appDir

Write-Host "[INFO] Done. Please check $AipFile manually."