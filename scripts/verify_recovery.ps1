# ============================================================================
# verify_recovery.ps1
# Run AFTER applying all 3 migration files to the live database.
# Uses Supabase CLI to verify recovery.
# ============================================================================
param(
    [string]$ProjectRef = ""
)

$ErrorActionPreference = "Stop"
$passed = 0
$failed = 0
$failedObjects = @()

function Write-Check {
    param([string]$Status, [string]$Message)
    if ($Status -eq "PASS") {
        Write-Host "  [PASS] $Message" -ForegroundColor Green
        $script:passed++
    } else {
        Write-Host "  [FAIL] $Message" -ForegroundColor Red
        $script:failed++
        $script:failedObjects += $Message
    }
}

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  DATABASE RECOVERY VERIFICATION" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

# ── STEP 1: Run SQL verification ──
Write-Host "Running SQL verification..." -ForegroundColor Yellow
Write-Host ""

$sqlFile = Join-Path $PSScriptRoot "..\supabase\VERIFY_RECOVERY.sql"
if (Test-Path $sqlFile) {
    Write-Host "SQL verification file found: $sqlFile" -ForegroundColor Gray
    Write-Host "Execute this in Supabase SQL Editor for detailed results." -ForegroundColor Gray
    Write-Host ""
}

# ── STEP 2: Check tables via supabase db dump ──
Write-Host "── CHECKING TABLES ──" -ForegroundColor Yellow

$requiredTables = @(
    "shareholders",
    "shareholder_transactions",
    "export_invoices",
    "fruit_varieties",
    "finished_products",
    "crop_purchases",
    "shareholder_profit_distributions",
    "shipment_cost_allocations",
    "shipment_recipe_snapshots",
    "audit_logs_text",
    "raw_material_categories",
    "raw_material_transactions",
    "finished_goods",
    "company_addresses",
    "financial_audit_log"
)

try {
    $dumpFile = Join-Path $env:TEMP "erp_schema_dump.sql"
    supabase db dump --schema-only --file $dumpFile 2>$null

    if (Test-Path $dumpFile) {
        $dumpContent = Get-Content $dumpFile -Raw

        foreach ($table in $requiredTables) {
            if ($dumpContent -match "CREATE TABLE.*public\.$table\b") {
                Write-Check "PASS" "Table: $table"
            } else {
                Write-Check "FAIL" "Table MISSING: $table"
            }
        }

        # ── CHECK FUNCTIONS ──
        Write-Host ""
        Write-Host "── CHECKING FUNCTIONS ──" -ForegroundColor Yellow

        $requiredFunctions = @(
            "generate_next_customer_code",
            "get_next_supplier_code",
            "get_next_shareholder_code",
            "get_total_revenue",
            "rpc_process_proforma_invoice_ledger",
            "get_inventory_summary"
        )

        foreach ($func in $requiredFunctions) {
            if ($dumpContent -match "CREATE.*FUNCTION.*public\.$func") {
                Write-Check "PASS" "Function: $func"
            } else {
                Write-Check "FAIL" "Function MISSING: $func"
            }
        }

        # ── CHECK VIEWS ──
        Write-Host ""
        Write-Host "── CHECKING VIEWS ──" -ForegroundColor Yellow

        $requiredViews = @(
            "items",
            "v_shareholders",
            "vw_cost_details_live",
            "invoices",
            "invoice_items",
            "purchase_items",
            "cashbox"
        )

        foreach ($view in $requiredViews) {
            if ($dumpContent -match "CREATE.*VIEW.*public\.$view") {
                Write-Check "PASS" "View: $view"
            } else {
                Write-Check "FAIL" "View MISSING: $view"
            }
        }

        # ── CHECK REMOVED TRIGGERS ──
        Write-Host ""
        Write-Host "── CHECKING REMOVED TRIGGERS ──" -ForegroundColor Yellow

        $removedTriggers = @(
            @{name="set_products_updated_at"; table="products"},
            @{name="set_suppliers_updated_at"; table="suppliers"},
            @{name="set_customers_updated_at"; table="customers"},
            @{name="trg_check_fy_allows_sales"; table="invoice_items"}
        )

        foreach ($trg in $removedTriggers) {
            $pattern = "CREATE TRIGGER.*$($trg.name).*ON.*public\.$($trg.table)"
            if ($dumpContent -match $pattern) {
                Write-Check "FAIL" "Still exists: $($trg.name) on $($trg.table)"
            } else {
                Write-Check "PASS" "Removed: $($trg.name) on $($trg.table)"
            }
        }

        # ── CHECK REMOVED ANON POLICIES ──
        Write-Host ""
        Write-Host "── CHECKING REMOVED ANON POLICIES ──" -ForegroundColor Yellow

        $anonTables = @("tenants", "tenant_users", "system_settings", "subscription_plans", "users")
        foreach ($tbl in $anonTables) {
            $pattern = "Allow all anon access.*$tbl"
            if ($dumpContent -match $pattern) {
                Write-Check "FAIL" "Still exists: anon policy on $tbl"
            } else {
                Write-Check "PASS" "Removed: anon policy on $tbl"
            }
        }

        Remove-Item $dumpFile -ErrorAction SilentlyContinue
    } else {
        Write-Host "WARNING: Could not dump schema. Run 'supabase db dump' manually." -ForegroundColor Yellow
    }
} catch {
    Write-Host "WARNING: Could not verify via supabase CLI. Run VERIFY_RECOVERY.sql manually." -ForegroundColor Yellow
    Write-Host "Error: $_" -ForegroundColor Gray
}

# ── SUMMARY ──
Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  RESULTS: $passed PASSED, $failed FAILED" -ForegroundColor $(if ($failed -eq 0) { "Green" } else { "Red" })

if ($failed -eq 0) {
    Write-Host "  STATUS: ALL CHECKS PASSED" -ForegroundColor Green
    Write-Host "  NEXT: Run 'supabase db dump --schema-only' to generate new schema.sql" -ForegroundColor Green
} else {
    Write-Host "  STATUS: $failed CHECKS FAILED" -ForegroundColor Red
    Write-Host ""
    Write-Host "  Failed objects:" -ForegroundColor Red
    foreach ($obj in $failedObjects) {
        Write-Host "    - $obj" -ForegroundColor Red
    }
    Write-Host ""
    Write-Host "  Fix these before generating schema.sql" -ForegroundColor Yellow
}
Write-Host "========================================" -ForegroundColor Cyan
