[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$rawTestRoot = Join-Path $projectRoot 'supabase\tests_raw'
$databaseContainer = 'supabase_db_POS_store'

# Keep this list explicit so moving or adding a security suite cannot silently
# change what the gate executes.
$rawTests = @(
    'rls.sql'
    'phase_2a_security.sql'
    'product_management_security.sql'
    'inventory_adjustment_security.sql'
    'sales_returns_voids_security.sql'
    'customer_khata_security.sql'
    'supplier_purchase_security.sql'
    'expense_security.sql'
    'owner_reporting_security.sql'
    'subscription_security.sql'
    'cashier_device_boundary_security.sql'
    'units_variants_security.sql'
)

$running = & docker inspect --format '{{.State.Running}}' $databaseContainer 2>$null
if ($LASTEXITCODE -ne 0 -or $running -ne 'true') {
    throw "Local Supabase database container '$databaseContainer' is not running. Run npx supabase@2.113.0 start first."
}

foreach ($testName in $rawTests) {
    $testPath = Join-Path $rawTestRoot $testName
    if (-not (Test-Path -LiteralPath $testPath -PathType Leaf)) {
        throw "Required raw SQL test is missing: $testPath"
    }

    Write-Host "RAW SQL: $testName"
    Get-Content -LiteralPath $testPath -Raw |
        & docker exec -i $databaseContainer psql -X -U postgres -d postgres -v ON_ERROR_STOP=1 -f -
    if ($LASTEXITCODE -ne 0) {
        throw "Raw SQL test failed: $testName"
    }
}

Write-Host "Raw SQL verification passed: $($rawTests.Count) files."
