# Creates deploy\tamreedy-server.tar.gz: only what the server needs (API, worker, admin dashboard, SQL, Docker files).
# Run from the project root:   powershell -ExecutionPolicy Bypass -File scripts\make-deploy-bundle.ps1
$ErrorActionPreference = 'Stop'
Set-Location (Join-Path $PSScriptRoot '..')
New-Item -ItemType Directory -Force deploy | Out-Null
$out = 'deploy/tamreedy-server.tar.gz'
if (Test-Path $out) { Remove-Item $out }

# Fail early if the lockfile is missing: the Docker build uses --frozen-lockfile.
if (-not (Test-Path pnpm-lock.yaml)) { throw 'pnpm-lock.yaml missing - run `pnpm install` first.' }

tar.exe -czf $out `
  --exclude=node_modules --exclude=dist --exclude=.env `
  --exclude=infra/docker/.env --exclude='*.log' `
  package.json pnpm-workspace.yaml pnpm-lock.yaml .dockerignore .env.example `
  apps/api apps/worker apps/admin_web infra scripts/enable-all-features.sql
if ($LASTEXITCODE -ne 0) { throw "tar failed ($LASTEXITCODE)" }

$mb = [math]::Round((Get-Item $out).Length / 1MB, 2)
Write-Host "OK: $out ($mb MB)"

# Also create deploy/tamreedy-server.zip for Plesk File Manager 1-click extraction
$zipOut = 'deploy/tamreedy-server.zip'
if (Test-Path $zipOut) { Remove-Item $zipOut -Force }
$tempStage = Join-Path ([System.IO.Path]::GetTempPath()) ([System.Guid]::NewGuid().ToString())
New-Item -ItemType Directory -Force $tempStage | Out-Null
try {
  tar.exe -xzf $out -C $tempStage
  Compress-Archive -Path "$tempStage\*" -DestinationPath $zipOut -Force
  $zipMb = [math]::Round((Get-Item $zipOut).Length / 1MB, 2)
  Write-Host "OK: $zipOut ($zipMb MB) [Ready for Plesk File Manager]"
} finally {
  Remove-Item -Recurse -Force $tempStage -ErrorAction SilentlyContinue
}

Write-Host 'Upload either file to the server and follow docs/PLESK_STEP_BY_STEP_AR.md'

