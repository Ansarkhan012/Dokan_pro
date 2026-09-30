$ErrorActionPreference = 'Stop'

function ConvertTo-Base64Url([byte[]]$Bytes) {
  return [Convert]::ToBase64String($Bytes).TrimEnd('=').Replace('+', '-').Replace('/', '_')
}

$statusJson = npx supabase@2.113.0 status -o json | ConvertFrom-Json
$apiUrl = [string]$statusJson.API_URL
$anonKey = [string]$statusJson.ANON_KEY
if ([string]::IsNullOrWhiteSpace($apiUrl) -or [string]::IsNullOrWhiteSpace($anonKey)) {
  throw 'Local Supabase API is not available.'
}

$rsa = [System.Security.Cryptography.RSA]::Create(2048)
$parameters = $rsa.ExportParameters($true)
$privateJwk = @{
  kty = 'RSA'
  n = ConvertTo-Base64Url $parameters.Modulus
  e = ConvertTo-Base64Url $parameters.Exponent
  d = ConvertTo-Base64Url $parameters.D
  p = ConvertTo-Base64Url $parameters.P
  q = ConvertTo-Base64Url $parameters.Q
  dp = ConvertTo-Base64Url $parameters.DP
  dq = ConvertTo-Base64Url $parameters.DQ
  qi = ConvertTo-Base64Url $parameters.InverseQ
  alg = 'RS256'
  key_ops = @('sign')
  ext = $false
} | ConvertTo-Json -Compress

$oldPrivate = $env:ENTITLEMENT_PRIVATE_JWK
$oldKeyId = $env:ENTITLEMENT_KEY_ID
$env:ENTITLEMENT_PRIVATE_JWK = $privateJwk
$env:ENTITLEMENT_KEY_ID = 'development-disposable'
$logOut = Join-Path $env:TEMP "dukaan-entitlement-e2e-$PID.out.log"
$logErr = Join-Path $env:TEMP "dukaan-entitlement-e2e-$PID.err.log"
$secretFile = Join-Path $env:TEMP "dukaan-entitlement-e2e-$PID.env"
[IO.File]::WriteAllLines($secretFile, @(
  "ENTITLEMENT_PRIVATE_JWK=$privateJwk",
  'ENTITLEMENT_KEY_ID=development-disposable'
))
$server = $null
$succeeded = $false
try {
  $server = Start-Process -FilePath 'npx.cmd' -ArgumentList @(
    'supabase@2.113.0', 'functions', 'serve', '--env-file', $secretFile
  ) -WorkingDirectory (Split-Path $PSScriptRoot -Parent) -WindowStyle Hidden -PassThru -RedirectStandardOutput $logOut -RedirectStandardError $logErr

  $ready = $false
  for ($attempt = 0; $attempt -lt 30; $attempt++) {
    Start-Sleep -Milliseconds 500
    try {
      Invoke-WebRequest -Uri "$apiUrl/functions/v1/issue-entitlement" -Method Post -ContentType 'application/json' -Body '{}' -ErrorAction Stop | Out-Null
    } catch {
      if ($_.Exception.Response -and [int]$_.Exception.Response.StatusCode -in 400,401,403) {
        $ready = $true
        break
      }
    }
    if ($server.HasExited) { throw 'Entitlement Edge Function stopped before becoming ready.' }
  }
  if (-not $ready) { throw 'Entitlement Edge Function did not become ready.' }

  flutter test tool/development_entitlement_e2e.dart `
    --dart-define=E2E_SUPABASE_URL=$apiUrl `
    --dart-define=E2E_SUPABASE_ANON_KEY=$anonKey `
    --dart-define=ENTITLEMENT_RSA_MODULUS_B64URL=$(ConvertTo-Base64Url $parameters.Modulus) `
    --dart-define=ENTITLEMENT_RSA_EXPONENT_B64URL=$(ConvertTo-Base64Url $parameters.Exponent)
  if ($LASTEXITCODE -ne 0) { throw 'Development entitlement issuance E2E failed.' }
  $succeeded = $true
} finally {
  if ($server -and -not $server.HasExited) { Stop-Process -Id $server.Id -Force }
  if (-not $succeeded) {
    if (Test-Path -LiteralPath $logOut) { Get-Content -LiteralPath $logOut -Tail 30 }
    if (Test-Path -LiteralPath $logErr) { Get-Content -LiteralPath $logErr -Tail 30 }
  }
  $rsa.Dispose()
  $env:ENTITLEMENT_PRIVATE_JWK = $oldPrivate
  $env:ENTITLEMENT_KEY_ID = $oldKeyId
  Remove-Item -LiteralPath $logOut,$logErr -Force -ErrorAction SilentlyContinue
  Remove-Item -LiteralPath $secretFile -Force -ErrorAction SilentlyContinue
}
