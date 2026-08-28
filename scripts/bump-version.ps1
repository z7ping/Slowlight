[CmdletBinding()]
param(
    [Parameter(Mandatory = $true, Position = 0)]
    [string]$Version,

    [Parameter(Mandatory = $true)]
    [ValidateRange(1, 2147483647)]
    [int]$BuildNumber,

    [string]$Date = (Get-Date -Format 'yyyy-MM-dd'),

    [switch]$DryRun
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$repositoryRoot = Split-Path -Parent $PSScriptRoot
$utf8NoBom = [System.Text.UTF8Encoding]::new($false)
$normalizedVersion = $Version.Trim()
if ($normalizedVersion.StartsWith('v', [StringComparison]::OrdinalIgnoreCase)) {
    $normalizedVersion = $normalizedVersion.Substring(1)
}

$semVerPattern = '^(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)(?:-([0-9A-Za-z-]+(?:\.[0-9A-Za-z-]+)*))?$'
$versionMatch = [regex]::Match($normalizedVersion, $semVerPattern)
if (-not $versionMatch.Success) {
    throw "版本格式无效：$Version。期望 X.Y.Z 或 X.Y.Z-prerelease，例如 1.0.0-alpha.1。"
}

if ($versionMatch.Groups[4].Success) {
    foreach ($identifier in $versionMatch.Groups[4].Value.Split('.')) {
        if ($identifier -match '^\d+$' -and $identifier.Length -gt 1 -and $identifier.StartsWith('0')) {
            throw "预发布数字标识不能包含前导零：$identifier"
        }
    }
}

try {
    [datetime]::ParseExact(
        $Date,
        'yyyy-MM-dd',
        [Globalization.CultureInfo]::InvariantCulture
    ) | Out-Null
} catch {
    throw "日期格式无效：$Date。期望 yyyy-MM-dd。"
}

$tag = "v$normalizedVersion"
$flutterVersion = "$normalizedVersion+$BuildNumber"
$paths = [ordered]@{
    Pubspec = Join-Path $repositoryRoot 'client\pubspec.yaml'
    Readme = Join-Path $repositoryRoot 'README.md'
    Changelog = Join-Path $repositoryRoot 'CHANGELOG.md'
}

foreach ($path in $paths.Values) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw "缺少版本文件：$path"
    }
}

$pubspec = [IO.File]::ReadAllText($paths.Pubspec)
$readme = [IO.File]::ReadAllText($paths.Readme)
$changelog = [IO.File]::ReadAllText($paths.Changelog)

$pubspecPattern = '(?m)^version:[^\r\n]*(?=\r?$)'
$pubspecMatches = [regex]::Matches($pubspec, $pubspecPattern)
if ($pubspecMatches.Count -ne 1) {
    throw "client/pubspec.yaml 应且只能包含一个顶层 version，实际找到 $($pubspecMatches.Count) 个。"
}
$updatedPubspec = [regex]::Replace(
    $pubspec,
    $pubspecPattern,
    "version: $flutterVersion"
)

$readmePattern = '代码版本基线为 `[^`]+`'
$readmeMatches = [regex]::Matches($readme, $readmePattern)
if ($readmeMatches.Count -ne 1) {
    throw "README.md 应且只能包含一个代码版本基线，实际找到 $($readmeMatches.Count) 个。"
}
$updatedReadme = [regex]::Replace(
    $readme,
    $readmePattern,
    "代码版本基线为 ``$normalizedVersion``"
)

if ([regex]::IsMatch($changelog, "(?m)^##[ \t]+\[$([regex]::Escape($tag))\](?:[ \t]+-|[ \t]*(?=\r?$))")) {
    throw "CHANGELOG.md 已存在 $tag 版本段，拒绝重复生成。"
}

$unreleasedHeading = [regex]::Match(
    $changelog,
    '(?m)^## \[Unreleased\][ \t]*(?=\r?$)'
)
if (-not $unreleasedHeading.Success) {
    throw 'CHANGELOG.md 缺少 ## [Unreleased]。'
}

$unreleasedContentStart = $unreleasedHeading.Index + $unreleasedHeading.Length
$nextReleaseSeparator = [regex]::Match(
    $changelog.Substring($unreleasedContentStart),
    '(?ms)^---\s*\r?\n\r?\n(?=## \[v)'
)
if (-not $nextReleaseSeparator.Success) {
    throw 'CHANGELOG.md 的 Unreleased 段后未找到历史版本分隔线。'
}

$separatorIndex = $unreleasedContentStart + $nextReleaseSeparator.Index
$unreleasedBody = $changelog.Substring(
    $unreleasedContentStart,
    $separatorIndex - $unreleasedContentStart
).Trim()
if ([string]::IsNullOrWhiteSpace($unreleasedBody) -or $unreleasedBody -eq '当前暂无未发布变更。') {
    throw 'CHANGELOG.md 的 Unreleased 段没有可发布内容。'
}

$newLine = if ($changelog.Contains("`r`n")) { "`r`n" } else { "`n" }
$historyStart = $separatorIndex + $nextReleaseSeparator.Length
$history = $changelog.Substring($historyStart).TrimStart("`r", "`n")
$changelogPrefix = $changelog.Substring(0, $unreleasedHeading.Index)
$updatedChangelog = @(
    $changelogPrefix.TrimEnd("`r", "`n")
    '## [Unreleased]'
    ''
    '当前暂无未发布变更。'
    ''
    '---'
    ''
    "## [$tag] - $Date"
    ''
    $unreleasedBody
    ''
    '---'
    ''
    $history.TrimEnd("`r", "`n")
) -join $newLine
$updatedChangelog += $newLine

Write-Host "版本：$normalizedVersion"
Write-Host "Flutter：$flutterVersion"
Write-Host "Tag：$tag"
Write-Host "日期：$Date"

if ($DryRun) {
    Write-Host 'Dry run：校验通过，未修改文件。'
    exit 0
}

$snapshots = @{}
foreach ($path in $paths.Values) {
    $snapshots[$path] = [IO.File]::ReadAllText($path)
}
$generatedFiles = Get-ChildItem -LiteralPath (Join-Path $repositoryRoot 'docs\_generated') -File
foreach ($file in $generatedFiles) {
    $snapshots[$file.FullName] = [IO.File]::ReadAllText($file.FullName)
}

try {
    [IO.File]::WriteAllText($paths.Pubspec, $updatedPubspec, $utf8NoBom)
    [IO.File]::WriteAllText($paths.Readme, $updatedReadme, $utf8NoBom)
    [IO.File]::WriteAllText($paths.Changelog, $updatedChangelog, $utf8NoBom)

    $python = Get-Command python -ErrorAction SilentlyContinue
    if (-not $python) {
        throw '缺少 Python，无法更新并验证生成文档。'
    }

    Push-Location $repositoryRoot
    try {
        & python scripts/docs/generate.py
        if ($LASTEXITCODE -ne 0) { throw '文档生成失败。' }

        & python scripts/docs/check.py
        if ($LASTEXITCODE -ne 0) { throw '文档一致性检查失败。' }

        & python scripts/docs/release_check.py $tag
        if ($LASTEXITCODE -ne 0) { throw '发布版本一致性检查失败。' }

        & python scripts/security/check_sensitive_files.py
        if ($LASTEXITCODE -ne 0) { throw '敏感信息检查失败。' }

        & git diff --check -- client/pubspec.yaml README.md CHANGELOG.md docs/_generated
        if ($LASTEXITCODE -ne 0) { throw '版本文件包含空白错误。' }
    } finally {
        Pop-Location
    }
} catch {
    foreach ($entry in $snapshots.GetEnumerator()) {
        [IO.File]::WriteAllText($entry.Key, $entry.Value, $utf8NoBom)
    }
    throw
}

Write-Host "版本文件已更新并通过检查。下一步可提交后创建 Tag：git tag $tag"
