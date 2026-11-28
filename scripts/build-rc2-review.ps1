param(
    [ValidateSet('patient_app', 'nurse_app', 'all')][string]$App = 'all'
)
$ErrorActionPreference = 'Stop'
$rc2Root = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$rc2Evidence = Join-Path $rc2Root 'docs/rc2-evidence'
$rc2Output = Join-Path $rc2Root 'handoff/rc2-artifacts'
New-Item -ItemType Directory -Force -Path $rc2Evidence, $rc2Output | Out-Null
$rc2Apps = if ($App -eq 'all') { @('patient_app', 'nurse_app') } else { @($App) }
foreach ($rc2App in $rc2Apps) {
    $rc2Label = $rc2App.Replace('_app', '')
    Push-Location (Join-Path $rc2Root "apps/$rc2App")
    try {
        foreach ($rc2Format in @('apk', 'appbundle')) {
            $rc2Log = Join-Path $rc2Evidence "$rc2Label-$rc2Format-build.txt"
            $rc2BuildArgs = @('--no-version-check', 'build', $rc2Format, '--release', '--no-pub',
                '--build-name=3.1.0-rc.2', '--build-number=7', '--dart-define=DEMO=false',
                '--dart-define=ENVIRONMENT=production',
                '--dart-define=API_BASE_URL=https://tamredy.dardus.com.sy/api')
            & flutter @rc2BuildArgs *> $rc2Log
            $rc2ExitCode = $LASTEXITCODE
            Add-Content -LiteralPath $rc2Log -Value "EXIT_CODE=$rc2ExitCode"
            if ($rc2ExitCode -ne 0) { throw "Build failed: $rc2App $rc2Format; see $rc2Log" }
            $rc2Extension = if ($rc2Format -eq 'apk') { 'apk' } else { 'aab' }
            $rc2Source = if ($rc2Format -eq 'apk') {
                'build/app/outputs/flutter-apk/app-release.apk'
            } else { 'build/app/outputs/bundle/release/app-release.aab' }
            # Existing project release configuration signs with the Android debug
            # keystore. Explicit naming prevents confusing these with store builds.
            $rc2Destination = Join-Path $rc2Output "tamreedy-$rc2Label-3.1.0-rc.2-debug-signed-release.$rc2Extension"
            Copy-Item -LiteralPath $rc2Source -Destination $rc2Destination -Force
            Get-Item -LiteralPath $rc2Destination | Select-Object FullName, Length
        }
    } finally { Pop-Location }
}
