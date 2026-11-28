param(
    [ValidateSet('patient_app', 'nurse_app', 'all')][string]$App = 'all',
    [switch]$Review,
    [int]$VersionCode,
    [ValidateSet('production','staging')][string]$Environment = 'production',
    [string]$ApiBaseUrl = 'https://tamredy.dardus.com.sy/api'
)
$ErrorActionPreference = 'Stop'
if (!$Review -and ($VersionCode -le 0 -or $Environment -ne 'production')) {
    throw 'Store release needs the verified next store version code and production configuration.'
}
if ($Review -and $VersionCode -le 0) { $VersionCode = 8 }
$uri = [Uri]$ApiBaseUrl
if (!$uri.IsAbsoluteUri -or $uri.IsLoopback -or $uri.UserInfo -or $uri.Query -or $uri.Fragment -or
    $uri.Host -in '10.0.2.2','0.0.0.0' -or $uri.Scheme -ne 'https') { throw 'Provide an external HTTPS API URL.' }
if ($Environment -eq 'production' -and $ApiBaseUrl.TrimEnd('/') -ne 'https://tamredy.dardus.com.sy/api') {
    throw 'The production API endpoint must match the approved /api URL.'
}
$root = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$output = Join-Path $root 'deploy/mobile'
New-Item -ItemType Directory -Path $output -Force | Out-Null
$apps = if ($App -eq 'all') { 'patient_app','nurse_app' } else { $App }
$oldSigning = $env:TAMREEDY_ANDROID_REVIEW_SIGNING
try {
    $env:TAMREEDY_ANDROID_REVIEW_SIGNING = if ($Review) { 'true' } else { 'false' }
    foreach ($project in $apps) {
        Push-Location (Join-Path $root "apps/$project")
        try {
            foreach ($kind in 'apk','appbundle') {
                $label = $project.Replace('_app','')
                $signature = if ($Review) { 'debug-signed-review' } else { 'store-signed' }
                $ext = if ($kind -eq 'apk') { 'apk' } else { 'aab' }
                $log = Join-Path $output "$label-$kind-build.log"
                flutter --no-version-check build $kind --release --no-pub '--build-name=3.1.0-rc.3' "--build-number=$VersionCode" '--dart-define=DEMO=false' "--dart-define=ENVIRONMENT=$Environment" "--dart-define=API_BASE_URL=$ApiBaseUrl" *> $log
                if ($LASTEXITCODE -ne 0) { throw "Build failed. See $log" }
                $file = if ($kind -eq 'apk') { 'build/app/outputs/flutter-apk/app-release.apk' } else { 'build/app/outputs/bundle/release/app-release.aab' }
                Copy-Item -LiteralPath $file -Destination (Join-Path $output "tamreedy-$label-3.1.0-rc.3-$signature.$ext") -Force
            }
        } finally { Pop-Location }
    }
} finally { $env:TAMREEDY_ANDROID_REVIEW_SIGNING = $oldSigning }
