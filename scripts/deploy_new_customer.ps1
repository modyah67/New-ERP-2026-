<#
.SYNOPSIS
Provision a brand-new Supabase project for a new client.
.PARAMETER ProjectRef
Supabase project reference (e.g., xyz123).
#>

param(
    [Parameter(Mandatory=$true)]
    [string]$ProjectRef
)

$ErrorActionPreference = "Stop"
$ProjectRoot = Split-Path -Parent $PSScriptRoot
$SeedsDir = Join-Path $ProjectRoot "supabase" "seeds"

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  New Customer Deployment" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

# Step 1: Link to project
Write-Host "[1/3] Linking to project: $ProjectRef ..." -ForegroundColor Yellow
supabase link $ProjectRef

# Step 2: Push baseline schema
Write-Host "[2/3] Pushing baseline schema..." -ForegroundColor Yellow
Push-Location (Join-Path $ProjectRoot "supabase")
try {
    supabase db push
} finally {
    Pop-Location
}

# Step 3: Seed required data
Write-Host "[3/3] Seeding required master data..." -ForegroundColor Yellow
$RequiredSeed = Join-Path $SeedsDir "seed_required.sql"
Push-Location (Join-Path $ProjectRoot "supabase")
try {
    supabase db seed --file $RequiredSeed
} finally {
    Pop-Location
}

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  ✅ Customer project ready!" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "The client can now start entering their own data." -ForegroundColor White
Write-Host "To load demo data: supabase db seed --file supabase\seeds\seed_demo.sql" -ForegroundColor White
