# Package a committed server source snapshot. Build images only for an explicit Linux target.
[CmdletBinding()]
param(
    [string]$SourceCommit = 'HEAD',
    [ValidateSet('source-build', 'linux/amd64', 'linux/arm64')]
    [string]$ServerArchitecture = 'source-build'
)
$ErrorActionPreference = 'Stop'
$rc3Root = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$rc3Output = Join-Path $rc3Root 'deploy'
if ($ServerArchitecture -ne 'source-build') {
    if (-not (Get-Command docker -ErrorAction SilentlyContinue)) { throw 'Docker Engine is required to build prebuilt images.' }
    & docker info *> $null
    if ($LASTEXITCODE -ne 0) { throw 'Docker Engine is unavailable. Use source-build mode.' }
}
& python (Join-Path $PSScriptRoot 'package-rc3-source.py') $rc3Root $rc3Output $SourceCommit $ServerArchitecture
if ($LASTEXITCODE -ne 0) { throw "RC3 packaging failed ($LASTEXITCODE)." }
