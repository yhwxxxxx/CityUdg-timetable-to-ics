$ErrorActionPreference = "Stop"

$root = (Get-Location).Path
$releaseDir = Join-Path $root "课表导入软件"
New-Item -ItemType Directory -Force -Path $releaseDir | Out-Null

$legacyReadme = Join-Path $releaseDir "使用说明.txt"
if (Test-Path -LiteralPath $legacyReadme) {
    Remove-Item -LiteralPath $legacyReadme -Force
}

$csc = Join-Path $env:WINDIR "Microsoft.NET\Framework64\v4.0.30319\csc.exe"
if (-not (Test-Path -LiteralPath $csc)) {
    $csc = Join-Path $env:WINDIR "Microsoft.NET\Framework\v4.0.30319\csc.exe"
}

& $csc `
    /nologo `
    /target:winexe `
    /platform:anycpu `
    /out:"$releaseDir\课表导入程序.exe" `
    /resource:"$root\timetable_importer.ps1",EmbeddedTimetableImporter `
    /reference:System.Windows.Forms.dll `
    /reference:System.Drawing.dll `
    "$root\TimetableImporterLauncher.cs"

if ($LASTEXITCODE -ne 0) {
    exit $LASTEXITCODE
}

Copy-Item -LiteralPath (Join-Path $root "使用说明.md") -Destination (Join-Path $releaseDir "使用说明.md") -Force
Get-ChildItem -LiteralPath $releaseDir | Select-Object Name,Length
