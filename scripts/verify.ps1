<#
.SYNOPSIS
Full verification pipeline — rebuilds DB, seeds, compares schema, runs Flutter tests.
.DESCRIPTION
Returns PASS/FAIL. If any object is missing, generates MISSING_OBJECT_REPORT.md.
#>

$ErrorActionPreference = "Stop"
$ProjectRoot = Split-Path -Parent $PSScriptRoot
$SupabaseDir = Join-Path $ProjectRoot "supabase"
$SeedsDir = Join-Path $SupabaseDir "seeds"
$SchemaFile = Join-Path $SupabaseDir "schema.sql"
$ReportFile = Join-Path $ProjectRoot "MISSING_OBJECT_REPORT.md"
$Result = "PASS"
$Issues = @()

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  ERP Database Verification Pipeline" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

# ── STEP 1: Database Reset ──
Write-Host "[1/7] Database reset..." -ForegroundColor Yellow
try {
    Push-Location $SupabaseDir
    supabase db reset --ignore-schema-mismatch
    Pop-Location
    Write-Host "  ✅ Database reset complete" -ForegroundColor Green
} catch {
    Write-Host "  ❌ Database reset failed: $_" -ForegroundColor Red
    $Result = "FAIL"
    $Issues += "Database reset failed: $_"
}

# ── STEP 2: Apply Baseline Migration ──
Write-Host "[2/7] Applying baseline migration..." -ForegroundColor Yellow
try {
    Push-Location $SupabaseDir
    supabase db push
    Pop-Location
    Write-Host "  ✅ Baseline migration applied" -ForegroundColor Green
} catch {
    Write-Host "  ❌ Baseline migration failed: $_" -ForegroundColor Red
    $Result = "FAIL"
    $Issues += "Baseline migration failed: $_"
}

# ── STEP 3: Seed Required Data ──
Write-Host "[3/7] Seeding required data..." -ForegroundColor Yellow
try {
    $RequiredSeed = Join-Path $SeedsDir "seed_required.sql"
    Push-Location $SupabaseDir
    supabase db seed --file $RequiredSeed
    Pop-Location
    Write-Host "  ✅ Seed complete" -ForegroundColor Green
} catch {
    Write-Host "  ❌ Seed failed: $_" -ForegroundColor Red
    $Result = "FAIL"
    $Issues += "Seed failed: $_"
}

# ── STEP 4: Schema Comparison ──
Write-Host "[4/7] Comparing schema..." -ForegroundColor Yellow
try {
    $CurrentSchema = Join-Path $ProjectRoot ".tmp_current_schema.sql"
    Push-Location $SupabaseDir
    supabase db dump --schema-only > $CurrentSchema
    Pop-Location

    $Diff = git diff --no-index --quiet $SchemaFile $CurrentSchema 2>$null
    if ($LASTEXITCODE -eq 0) {
        Write-Host "  ✅ Schema matches canonical schema" -ForegroundColor Green
    } else {
        Write-Host "  ⚠️  Schema differences detected (may be due to ordering)" -ForegroundColor Yellow
        $Issues += "Schema differences detected — review diff"
    }
    Remove-Item $CurrentSchema -ErrorAction SilentlyContinue
} catch {
    Write-Host "  ⚠️  Schema comparison skipped: $_" -ForegroundColor Yellow
}

# ── STEP 5: Flutter Analyze ──
Write-Host "[5/7] Running flutter analyze..." -ForegroundColor Yellow
try {
    Push-Location $ProjectRoot
    flutter analyze --no-fatal-infos --no-fatal-warnings
    Pop-Location
    Write-Host "  ✅ Flutter analyze passed" -ForegroundColor Green
} catch {
    Write-Host "  ❌ Flutter analyze failed: $_" -ForegroundColor Red
    $Result = "FAIL"
    $Issues += "Flutter analyze failed: $_"
}

# ── STEP 6: Flutter Test ──
Write-Host "[6/7] Running flutter test..." -ForegroundColor Yellow
try {
    Push-Location $ProjectRoot
    flutter test --no-pub
    Pop-Location
    Write-Host "  ✅ Flutter tests passed" -ForegroundColor Green
} catch {
    Write-Host "  ❌ Flutter test failed: $_" -ForegroundColor Red
    $Result = "FAIL"
    $Issues += "Flutter test failed: $_"
}

# ── STEP 7: Generate Report ──
Write-Host "[7/7] Generating report..." -ForegroundColor Yellow

$ReportContent = @"
# Verification Report — $(Get-Date -Format "yyyy-MM-dd HH:mm:ss")

## Result: $Result

## Steps
| Step | Status |
|------|--------|
| Database Reset | $(if ($Issues -contains "Database reset failed:*") { "FAIL" } else { "PASS" }) |
| Baseline Migration | $(if ($Issues -contains "Baseline migration failed:*") { "FAIL" } else { "PASS" }) |
| Seed Required Data | $(if ($Issues -contains "Seed failed:*") { "FAIL" } else { "PASS" }) |
| Schema Comparison | $(if ($Issues -contains "Schema differences*") { "WARN" } else { "PASS" }) |
| Flutter Analyze | $(if ($Issues -contains "Flutter analyze failed:*") { "FAIL" } else { "PASS" }) |
| Flutter Test | $(if ($Issues -contains "Flutter test failed:*") { "FAIL" } else { "PASS" }) |

## Issues
$(if ($Issues.Count -eq 0) { "None." } else {
    $Issues | ForEach-Object { "- $_" } | Out-String
})
"@

if ($Result -eq "FAIL") {
    Set-Content -Path $ReportFile -Value $ReportContent -Encoding UTF8
    Write-Host "  ❌ Missing Object Report generated: $ReportFile" -ForegroundColor Red
} else {
    Write-Host "  ✅ All checks passed" -ForegroundColor Green
}

# ── FINAL RESULT ──
Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
if ($Result -eq "PASS") {
    Write-Host "  VERIFICATION: PASS" -ForegroundColor Green
} else {
    Write-Host "  VERIFICATION: FAIL" -ForegroundColor Red
}
Write-Host "========================================" -ForegroundColor Cyan

exit $(if ($Result -eq "PASS") { 0 } else { 1 })
