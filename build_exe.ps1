param(
    [string]$CertificateThumbprint = $env:TIMETABLE_IMPORTER_SIGNING_THUMBPRINT
)

$ErrorActionPreference = "Stop"

$root = $PSScriptRoot
$releaseDir = Join-Path $root "课表导入软件"
New-Item -ItemType Directory -Force -Path $releaseDir | Out-Null

$legacyReadme = Join-Path $releaseDir "使用说明.txt"
if (Test-Path -LiteralPath $legacyReadme) {
    Remove-Item -LiteralPath $legacyReadme -Force
}

$legacyCover = Join-Path $releaseDir "程序封面.png"
if (Test-Path -LiteralPath $legacyCover) {
    Remove-Item -LiteralPath $legacyCover -Force
}

$csc = Join-Path $env:WINDIR "Microsoft.NET\Framework64\v4.0.30319\csc.exe"
if (-not (Test-Path -LiteralPath $csc)) {
    $csc = Join-Path $env:WINDIR "Microsoft.NET\Framework\v4.0.30319\csc.exe"
}

$automationAssembly = Join-Path $env:WINDIR "System32\WindowsPowerShell\v1.0\System.Management.Automation.dll"
if (-not (Test-Path -LiteralPath $automationAssembly)) {
    $gacRoot = Join-Path $env:WINDIR "Microsoft.NET\assembly\GAC_MSIL\System.Management.Automation"
    $automationAssembly = Get-ChildItem -LiteralPath $gacRoot -Filter "System.Management.Automation.dll" -Recurse -ErrorAction SilentlyContinue |
        Select-Object -First 1 -ExpandProperty FullName
}
if (-not $automationAssembly -or -not (Test-Path -LiteralPath $automationAssembly)) {
    throw "找不到 Windows PowerShell 5.1 自动化程序集。"
}

$exePath = Join-Path $releaseDir "课表导入程序.exe"
& $csc `
    /nologo `
    /target:winexe `
    /platform:anycpu `
    /optimize+ `
    /win32manifest:"$root\app.manifest" `
    /win32icon:"$root\assets\app-icon.ico" `
    /out:"$exePath" `
    /reference:System.Windows.Forms.dll `
    /reference:System.Drawing.dll `
    /reference:"$automationAssembly" `
    "$root\TimetableImporterLauncher.cs"

if ($LASTEXITCODE -ne 0) {
    exit $LASTEXITCODE
}

Copy-Item -LiteralPath (Join-Path $root "timetable_importer.ps1") -Destination (Join-Path $releaseDir "timetable_importer.ps1") -Force
Copy-Item -LiteralPath (Join-Path $root "使用说明.md") -Destination (Join-Path $releaseDir "使用说明.md") -Force
Copy-Item -LiteralPath (Join-Path $root "SECURITY.md") -Destination (Join-Path $releaseDir "SECURITY.md") -Force

if ($CertificateThumbprint) {
    $kitsRoot = Join-Path ${env:ProgramFiles(x86)} "Windows Kits\10\bin"
    $signTool = Get-ChildItem -LiteralPath $kitsRoot -Filter "signtool.exe" -Recurse -ErrorAction SilentlyContinue |
        Where-Object { $_.FullName -match '\\x64\\signtool\.exe$' } |
        Sort-Object FullName -Descending |
        Select-Object -First 1

    if ($null -eq $signTool) {
        throw "已提供签名证书指纹，但未找到 Windows SDK signtool.exe。"
    }

    & $signTool.FullName sign `
        /sha1 $CertificateThumbprint `
        /fd SHA256 `
        /tr "http://timestamp.digicert.com" `
        /td SHA256 `
        $exePath

    if ($LASTEXITCODE -ne 0) {
        exit $LASTEXITCODE
    }
}

$hashFiles = @(
    $exePath,
    (Join-Path $releaseDir "timetable_importer.ps1"),
    (Join-Path $releaseDir "使用说明.md"),
    (Join-Path $releaseDir "SECURITY.md")
)
$checksums = foreach ($file in $hashFiles) {
    $hash = (Get-FileHash -LiteralPath $file -Algorithm SHA256).Hash.ToLowerInvariant()
    "$hash  $([IO.Path]::GetFileName($file))"
}
[IO.File]::WriteAllLines((Join-Path $releaseDir "SHA256SUMS.txt"), $checksums, [Text.UTF8Encoding]::new($false))

Get-ChildItem -LiteralPath $releaseDir | Select-Object Name, Length
