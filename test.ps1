# Путь к файлам
$aipFile = "C:\Users\BlackBricks\Applications\Neuro installer\installer_win\Neuro Desktop 2.aip"
$appDir = "C:\Users\BlackBricks\Applications\Neuro installer\app"

if (-not (Test-Path -Path $aipFile -PathType Leaf)) {
    Write-Error "[ERROR] AIP file not found: $aipFile"
    exit 1
}

if (-not (Test-Path -Path $AppDir -PathType Container)) {
    Write-Error "[ERROR] App directory not found: $appDir"
    exit 1
}

function Update-AipJarReferences {
    param (
        [string]$AipFile,
        [string]$AppDir
    )

    Write-Host "[INFO] Updating .jar file references in $AipFile from $AppDir"

    # Считаем весь файл в память
    $content = Get-Content -Path $AipFile -Raw

    # Получаем список jar-файлов
    $jarFiles = Get-ChildItem -Path $AppDir -Filter *.jar

    foreach ($jar in $jarFiles) {
        $baseName = $jar.Name

        # Регулярка для поиска префикса (до -32хзначного хеша и .jar)
        if ($baseName -match "^(.*)-[0-9a-f]{32}\.jar$") {
            $prefix = $matches[1]
        }
        else {
            Write-Warning "[WARNING] $baseName does not match expected pattern, skipping"
            continue
        }

        Write-Host "[INFO] Updating references for $prefix"

        # Экранируем точки для regex
        $escapedPrefix = [regex]::Escape($prefix)
        # Паттерн для поиска старой строки
        $pattern = "<ROW File=`"$escapedPrefix-[0-9a-f]{32}\.jar`" Component_=`"(.*?)\`" FileName=`"(.*?)\`" Attributes=`"(.*?)\`" SourcePath=`"\.\.\\app\\$escapedPrefix-[0-9a-f]{32}\.jar`" SelfReg=`"(.*?)\`"/>"

        # Создаем новую строку с сохранением атрибутов
        $newRow = $content -replace $pattern, {
            param($match)
            $component = $match.Groups[1].Value
            $fileName = $match.Groups[2].Value
            $attributes = $match.Groups[3].Value
            $selfReg = $match.Groups[4].Value
            "<ROW File=`"$baseName`" Component_=`"$component`" FileName=`"$fileName`" Attributes=`"$attributes`" SourcePath=`"..\\app\\$baseName`" SelfReg=`"$selfReg`"/>"
        }

        # Если замена произошла, обновляем контент
        if ($newRow -ne $content) {
            $content = $newRow
        }
    }

    # Записываем обратно в файл
    Set-Content -Path $AipFile -Value $content -Encoding UTF8

    Write-Host "[INFO] All .jar references updated"
}

Update-AipJarReferences -AipFile $aipFile -AppDir $appDir

Write-Host "[INFO] Done. Please check $aipFile manually."