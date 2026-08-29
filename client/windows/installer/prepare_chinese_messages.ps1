$ErrorActionPreference = 'Stop'

$sourceCommit = '1ff90acc4ed4aee82b1cda43253243deee3daed4'
$expectedBlobSha = '30d997321197c7c96d8e111e9ddd6c0ca8da5f09'
$sourceUrl = "https://raw.githubusercontent.com/kira-96/Inno-Setup-Chinese-Simplified-Translation/$sourceCommit/ChineseSimplified.isl"
$destination = Join-Path $PSScriptRoot 'ChineseSimplified.isl'

Write-Host "Downloading pinned Simplified Chinese Inno Setup messages: $sourceCommit"
Invoke-WebRequest -Uri $sourceUrl -OutFile $destination -UseBasicParsing

$actualBlobSha = (& git hash-object -- $destination).Trim()
if ($LASTEXITCODE -ne 0) {
  Remove-Item $destination -Force -ErrorAction SilentlyContinue
  throw 'Unable to calculate Git blob hash for ChineseSimplified.isl.'
}

if ($actualBlobSha -ne $expectedBlobSha) {
  Remove-Item $destination -Force -ErrorAction SilentlyContinue
  throw "ChineseSimplified.isl integrity check failed. Expected $expectedBlobSha, got $actualBlobSha."
}

Write-Host "ChineseSimplified.isl verified: $actualBlobSha"
