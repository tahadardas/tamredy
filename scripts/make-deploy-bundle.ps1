# Package the server source and Docker configuration for SSH or Plesk updates.
$ErrorActionPreference = 'Stop'
Set-Location (Join-Path $PSScriptRoot '..')
New-Item -ItemType Directory -Force deploy | Out-Null

if (-not (Test-Path pnpm-lock.yaml)) {
    throw 'pnpm-lock.yaml is required for frozen Docker installs.'
}

$excluded = @(
    '--exclude=node_modules', '--exclude=dist', '--exclude=coverage',
    '--exclude=.env', '--exclude=infra/docker/.env',
    '--exclude=infra/docker/secrets', '--exclude=*.log', '--exclude=*.tsbuildinfo'
)
$included = @(
    'package.json', 'pnpm-workspace.yaml', 'pnpm-lock.yaml',
    '.dockerignore', '.env.example', 'apps/api', 'apps/worker',
    'apps/admin_web', 'infra', 'scripts/enable-all-features.sql'
)
$outputs = @(
    @{ File = 'deploy/tamreedy-server.tar.gz'; Staged = 'deploy/.tamreedy-server.staging.tar.gz'; Format = '-czf' },
    @{ File = 'deploy/tamreedy-server.zip'; Staged = 'deploy/.tamreedy-server.staging.zip'; Format = '-acf' }
)
$required = @(
    '.dockerignore', 'pnpm-lock.yaml',
    'apps/worker/src/dispatch.ts', 'infra/docker/docker-compose.prod.yml'
)

try {
    foreach ($output in $outputs) {
        & tar.exe $output.Format $output.Staged @excluded @included
        if ($LASTEXITCODE -ne 0) { throw "tar failed for $($output.File) ($LASTEXITCODE)" }

        $entries = @(tar.exe -tf $output.Staged)
        if ($LASTEXITCODE -ne 0) { throw "Cannot read $($output.Staged)" }
        foreach ($entry in $required) {
            if ($entry -notin $entries) { throw "Missing archive entry $entry" }
        }
        if ($entries -match '(^|/)(secrets(?:/|$)|\.env(?:$|\.(?!example$|prod\.example$)))') {
            throw "Archive contains deployment secrets or environment files."
        }
    }

    foreach ($output in $outputs) {
        Move-Item -LiteralPath $output.Staged -Destination $output.File -Force
        $mb = [math]::Round((Get-Item $output.File).Length / 1MB, 2)
        Write-Host "OK: $($output.File) ($mb MB)"
    }
} finally {
    foreach ($output in $outputs) {
        if (Test-Path -LiteralPath $output.Staged) {
            Remove-Item -LiteralPath $output.Staged -Force
        }
    }
}
