$ErrorActionPreference = "Stop"
$root = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$release = Join-Path $root "课表导入软件"
$exe = Join-Path $release "课表导入程序.exe"
$source = Join-Path $root "timetable_importer.ps1"
$releaseScript = Join-Path $release "timetable_importer.ps1"
$icon = Join-Path $root "assets\app-icon.ico"

if (-not (Test-Path -LiteralPath $exe)) { throw "Executable is missing" }
if (-not (Test-Path -LiteralPath $releaseScript)) { throw "Release script is missing" }
if (-not (Test-Path -LiteralPath $icon)) { throw "Application icon is missing" }

$sourceHash = (Get-FileHash -LiteralPath $source -Algorithm SHA256).Hash
$releaseScriptHash = (Get-FileHash -LiteralPath $releaseScript -Algorithm SHA256).Hash
if ($sourceHash -ne $releaseScriptHash) { throw "Release contains an outdated script" }

$readmeHash = (Get-FileHash -LiteralPath (Join-Path $root "使用说明.md") -Algorithm SHA256).Hash
$releaseReadmeHash = (Get-FileHash -LiteralPath (Join-Path $release "使用说明.md") -Algorithm SHA256).Hash
if ($readmeHash -ne $releaseReadmeHash) { throw "Release instructions are outdated" }

$assembly = [Reflection.Assembly]::LoadFile($exe)
$product = $assembly.GetCustomAttributes([Reflection.AssemblyProductAttribute], $false) | Select-Object -First 1
if ($null -eq $product -or $product.Product -ne "课表导入程序") { throw "Product metadata is missing" }

$launcherSource = [IO.File]::ReadAllText((Join-Path $root "TimetableImporterLauncher.cs"))
$forbiddenPatterns = @("ExecutionPolicy", "CreateNoWindow", "GetTempPath", "Process.Start", "powershell.exe")
foreach ($pattern in $forbiddenPatterns) {
    if ($launcherSource.Contains($pattern)) { throw "Launcher contains unsafe behavior: $pattern" }
}

$buildSource = [IO.File]::ReadAllText((Join-Path $root "build_exe.ps1"))
if (-not $buildSource.Contains('/win32icon:')) { throw "Application icon is not embedded in the executable" }

$checksums = Join-Path $release "SHA256SUMS.txt"
if (-not (Test-Path -LiteralPath $checksums)) { throw "SHA256 checksums are missing" }
if (-not (Test-Path -LiteralPath (Join-Path $release "SECURITY.md"))) { throw "Security guidance is missing" }

Write-Host "Build test passed"
