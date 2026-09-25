$ErrorActionPreference = "Stop"
$root = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$release = Join-Path $root "课表导入软件"
$exe = Join-Path $release "课表导入程序.exe"
$source = Join-Path $root "timetable_importer.ps1"

$assembly = [Reflection.Assembly]::LoadFile($exe)
$stream = $assembly.GetManifestResourceStream("EmbeddedTimetableImporter")
if ($null -eq $stream) { throw "Embedded script is missing" }
try {
    $reader = [IO.StreamReader]::new($stream, [Text.Encoding]::UTF8)
    $embedded = $reader.ReadToEnd()
}
finally {
    if ($null -ne $reader) { $reader.Dispose() }
    else { $stream.Dispose() }
}

$current = [IO.File]::ReadAllText($source, [Text.Encoding]::UTF8)
if ($embedded -cne $current) { throw "Executable contains an outdated script" }

$readmeHash = (Get-FileHash -LiteralPath (Join-Path $root "使用说明.md") -Algorithm SHA256).Hash
$releaseReadmeHash = (Get-FileHash -LiteralPath (Join-Path $release "使用说明.md") -Algorithm SHA256).Hash
if ($readmeHash -ne $releaseReadmeHash) { throw "Release instructions are outdated" }

Write-Host "Build test passed"
