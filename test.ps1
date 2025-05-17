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

        # Убираем старые ссылки, экранируем точки для regex
        $escapedPrefix = [regex]::Escape($prefix)
        # Паттерн для строки, которая будет удалена
        $pattern = "<ROW File=`"$escapedPrefix.*\.jar`" .*SourcePath=`"..\\\\app\\\\$escapedPrefix.*\.jar`""

        # Удаляем все такие строки из контента
        $content = $content -replace "$pattern.*`r?`n", ""

        # Создаем новую строку (пример)
        $newRow = "<ROW File=""$($baseName -replace '\.','')0"" Component_=""maincomponent"" FileName=""$($baseName.ToUpper())"" Attributes=""0"" SourcePath=""..\\app\\$baseName"" SelfReg=""false""/>"

        # Вставляем новую строку перед первым <ROW
        $content = $content -replace "(<ROW )", "$newRow`n$1", 1
    }

    # Записываем обратно в файл
    Set-Content -Path $AipFile -Value $content -Encoding UTF8

    Write-Host "[INFO] All .jar references updated"
}

Update-AipJarReferences -AipFile $aipFile -AppDir $appDir

Write-Host "[INFO] Done. Please check $aipFile manually."
