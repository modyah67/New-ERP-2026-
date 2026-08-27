<#
.SYNOPSIS
Reset the local Supabase development database.
.DESCRIPTION
Drops everything, applies the baseline migration, seeds required data,
and optionally launches Flutter.
#>

$ErrorActionPreference = "Stop"
$ProjectRoot = Split-Path -Parent $PSScriptRoot
$SupabaseDir = Join-Path $ProjectRoot "supabase"
$SeedsDir = Join-Path $SupabaseDir "seeds"

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  ERP Development Database Reset" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

# Step 1: Reset database
Write-Host "[1/4] Resetting Supabase database..." -ForegroundColor Yellow
Push-Location $SupabaseDir
try {
    supabase db reset --ignore-schema-mismatch
} finally {
    Pop-Location
}
Write-Host "  ✅ Database reset complete" -ForegroundColor Green

# Step 2: Apply baseline migration
Write-Host "[2/4] Applying baseline migration..." -ForegroundColor Yellow
Push-Location $SupabaseDir
try {
    supabase db push
} finally {
    Pop-Location
}
Write-Host "  ✅ Baseline migration applied" -ForegroundColor Green

# Step 3: Seed required data
Write-Host "[3/4] Seeding required master data..." -ForegroundColor Yellow
$RequiredSeed = Join-Path $SeedsDir "seed_required.sql"
Push-Location $SupabaseDir
try {
    supabase db seed --file $RequiredSeed
} finally {
    Pop-Location
}
Write-Host "  ✅ Required seed complete" -ForegroundColor Green

# Step 4: Optionally launch Flutter
$LaunchFlutter = $args -contains "--launch"
if ($LaunchFlutter) {
    Write-Host "[4/4] Launching Flutter ERP..." -ForegroundColor Yellow
    Push-Location $ProjectRoot
    try {
        flutter run -d windows
    } finally {
        Pop-Location
    }
} else {
    Write-Host "[4/4] Skipping Flutter launch (use --launch to start)" -ForegroundColor Yellow
}

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  ✅ Development reset complete!" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "To launch Flutter:  .\scripts\reset_dev.ps1 --launch" -ForegroundColor White
Write-Host "To seed demo data:  supabase db seed --file supabase\seeds\seed_demo.sql" -ForegroundColor White
