[CmdletBinding()]
param(
    [string]$Version,
    [string]$ServerUrl = $(
        if ($env:SERVER_URL) { $env:SERVER_URL } else { 'http://localhost:8080/api' }
    )
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$projectRoot = Split-Path -Parent $PSScriptRoot
$pubspecPath = Join-Path $projectRoot 'pubspec.yaml'

if (-not (Get-Command flutter -ErrorAction SilentlyContinue)) {
    throw '缺少 Flutter。请先安装 Flutter 并加入 PATH。'
}
if (-not (Get-Command Compress-Archive -ErrorAction SilentlyContinue)) {
    throw '当前 PowerShell 不支持 Compress-Archive，请使用 PowerShell 7。'
}
if (-not (Test-Path -LiteralPath $pubspecPath -PathType Leaf)) {
    throw "未找到 Flutter 工程文件：$pubspecPath"
}

if (-not $Version) {
    $versionLine = Select-String -LiteralPath $pubspecPath -Pattern '^version:\s*(.+)$'
    if (-not $versionLine) {
        throw '无法从 pubspec.yaml 读取版本号。'
    }
    $Version = ($versionLine.Matches[0].Groups[1].Value -split '\+')[0]
}

& flutter --version | Out-Null
if ($LASTEXITCODE -ne 0) {
    throw 'Flutter 当前不可用，请先完成 Windows 桌面工具链配置。'
}

Write-Host '═══════════════════════════════════════'
Write-Host ' Slowlight Windows Build'
Write-Host " Server: $ServerUrl"
Write-Host " Version: $Version"
Write-Host '═══════════════════════════════════════'

Push-Location $projectRoot
try {
    & flutter build windows --release "--dart-define=SERVER_URL=$ServerUrl"
    if ($LASTEXITCODE -ne 0) {
        throw "Flutter Windows 构建失败，退出码：$LASTEXITCODE"
    }
} finally {
    Pop-Location
}

$outputDirectory = Join-Path $projectRoot 'build\windows\x64\runner\Release'
if (-not (Test-Path -LiteralPath $outputDirectory -PathType Container)) {
    throw "构建结束但未找到 Windows Release 目录：$outputDirectory"
}

$archivePath = Join-Path $projectRoot "build\slowlight-windows-$Version.zip"
Compress-Archive -Path (Join-Path $outputDirectory '*') -DestinationPath $archivePath -Force
if (-not (Test-Path -LiteralPath $archivePath -PathType Leaf)) {
    throw "Windows 压缩包生成失败：$archivePath"
}

Write-Host ''
Write-Host "✓ Windows: $outputDirectory"
Write-Host "✓ Archive: $archivePath"
Write-Host '  可通过 GitHub Actions 发布，或使用 release.sh 上传到已有 GitHub tag'
