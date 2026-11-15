<#
.SYNOPSIS
Deploys the clean database schema, master Chart of Accounts, and latest RPCs
(two-stage seasonal closures, carton returns, item-bound routing) to a fresh Supabase project.

.PARAMETER ProjectRef
The Supabase project reference (default: rakdzuvlauphupkywoik)
#>

param(
    [Parameter(Mandatory=$false)]
    [string]$ProjectRef = "rakdzuvlauphupkywoik"
)

$ErrorActionPreference = "Stop"
$ProjectRoot = Split-Path -Parent $PSScriptRoot
$SupabaseDir = Join-Path $ProjectRoot "supabase"
$MasterSplitDir = Join-Path $SupabaseDir "scripts" "master_split"
$BaselineSchema = Join-Path $SupabaseDir "migrations" "20260721000000_initial_schema.sql"

Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host "  Fruity Farms ERP - Fresh Instance Deployment" -ForegroundColor Cyan
Write-Host "  Target Project: $ProjectRef" -ForegroundColor Yellow
Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host ""

# Step 1: Link to Supabase project
Write-Host "[1/4] Linking project CLI to: $ProjectRef ..." -ForegroundColor Yellow
Push-Location $SupabaseDir
try {
    supabase link --project-ref $ProjectRef
} catch {
    Write-Warning "Could not automatically link via CLI. You can apply the scripts directly via Supabase SQL Editor."
} finally {
    Pop-Location
}

Write-Host ""
Write-Host "[2/4] Database Deployment Options:" -ForegroundColor Cyan
Write-Host "Option A: Automated Pipeline Script (Fastest & 1-Click with DB password):" -ForegroundColor White
Write-Host "  dart run scripts/apply_master_pipeline.dart" -ForegroundColor Green
Write-Host "  (Or set `$env:SUPABASE_DB_PASSWORD='your_password' before running)" -ForegroundColor Gray
Write-Host ""
Write-Host "Option B: Supabase Dashboard SQL Editor (100% Reliable via Web UI):" -ForegroundColor White
Write-Host "  1. Open: https://supabase.com/dashboard/project/$ProjectRef/sql/new" -ForegroundColor Green
Write-Host "  2. Run Baseline Schema: supabase\migrations\20260721000000_initial_schema.sql" -ForegroundColor White
Write-Host "  3. Run Master Part 1:   supabase\scripts\master_split\01_master_reset_cleanup_and_coa.sql" -ForegroundColor White
Write-Host "  4. Run Master Part 2:   supabase\scripts\master_split\02_master_suppliers_and_operations.sql" -ForegroundColor White
Write-Host "  5. Run Master Part 3:   supabase\scripts\master_split\03_master_cost_centers_and_rpcs.sql" -ForegroundColor White
Write-Host ""
Write-Host "Option C: PostgreSQL Direct / Pooler Connection String:" -ForegroundColor White
Write-Host "  postgresql://postgres.$($ProjectRef):[YOUR-PASSWORD]@aws-0-eu-central-1.pooler.supabase.com:5432/postgres" -ForegroundColor Yellow
Write-Host ""
Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host "  Deployment Package Ready!" -ForegroundColor Green
Write-Host "==========================================================" -ForegroundColor Cyan
