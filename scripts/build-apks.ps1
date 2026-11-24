param(
    [ValidateSet('pilot', 'release', 'all')]
    [string]$Target = 'all',
    [string]$PilotUrl = 'http://85.215.243.237:18300',
    [string]$ReleaseUrl = 'https://tamredy.dardus.com.sy/api'
)

$ErrorActionPreference = 'Stop'
$rootDir = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
Set-Location $rootDir

$deployApkDir = Join-Path $rootDir 'deploy\apk'
if (-not (Test-Path $deployApkDir)) {
    New-Item -ItemType Directory -Force -Path $deployApkDir | Out-Null
}

function Build-AppApk {
    param(
        [string]$AppName,
        [string]$AppLabel,
        [string]$Flavor,
        [string]$ApiUrl,
        [string]$Environment
    )

    Write-Host "`n========================================================" -ForegroundColor Cyan
    Write-Host "Building $AppLabel ($Flavor) -> API: $ApiUrl" -ForegroundColor Cyan
    Write-Host "========================================================" -ForegroundColor Cyan

    $appPath = Join-Path $rootDir "apps\$AppName"
    Push-Location $appPath

    try {
        & flutter build apk --release `
            "--dart-define=DEMO=false" `
            "--dart-define=ENVIRONMENT=$Environment" `
            "--dart-define=API_BASE_URL=$ApiUrl"

        if ($LASTEXITCODE -ne 0) {
            throw "Flutter build apk failed for $AppName ($Flavor)"
        }

        $sourceApk = Join-Path $appPath "build\app\outputs\flutter-apk\app-release.apk"
        if (-not (Test-Path $sourceApk)) {
            throw "Output APK not found at $sourceApk"
        }

        $destApkName = "tamreedy-$AppLabel-$Flavor.apk"
        $destApk = Join-Path $deployApkDir $destApkName
        Copy-Item -Path $sourceApk -Destination $destApk -Force

        $sizeMb = [math]::Round((Get-Item $destApk).Length / 1MB, 2)
        Write-Host "SUCCESS: Generated $destApk ($sizeMb MB)" -ForegroundColor Green
    }
    finally {
        Pop-Location
    }
}

if ($Target -eq 'pilot' -or $Target -eq 'all') {
    Build-AppApk -AppName 'patient_app' -AppLabel 'patient' -Flavor 'pilot' -ApiUrl $PilotUrl -Environment 'staging'
    Build-AppApk -AppName 'nurse_app' -AppLabel 'nurse' -Flavor 'pilot' -ApiUrl $PilotUrl -Environment 'staging'
}

if ($Target -eq 'release' -or $Target -eq 'all') {
    Build-AppApk -AppName 'patient_app' -AppLabel 'patient' -Flavor 'release' -ApiUrl $ReleaseUrl -Environment 'production'
    Build-AppApk -AppName 'nurse_app' -AppLabel 'nurse' -Flavor 'release' -ApiUrl $ReleaseUrl -Environment 'production'
}

Write-Host "`n========================================================" -ForegroundColor Green
Write-Host "All APKs generated successfully in: $deployApkDir" -ForegroundColor Green
Write-Host "========================================================" -ForegroundColor Green
Get-ChildItem $deployApkDir -Filter "*.apk" | Select-Object Name, Length, LastWriteTime | Format-Table -AutoSize
