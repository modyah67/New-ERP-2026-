<#
.SYNOPSIS
Restore a Supabase database from a backup file.
.PARAMETER BackupFile
Path to the .sql dump produced by backup.ps1.
#>

param(
    [Parameter(Mandatory=$true)]
    [string]$BackupFile
)

$ErrorActionPreference = "Stop"
$ProjectRoot = Split-Path -Parent $PSScriptRoot

if (-not (Test-Path $BackupFile)) {
    Write-Error "Backup file not found: $BackupFile"
    exit 1
}

Write-Host "Restoring database from $BackupFile ..." -ForegroundColor Yellow

# Reset the database first
Push-Location (Join-Path $ProjectRoot "supabase")
try {
    supabase db reset --ignore-schema-mismatch

    # Restore from dump
    Write-Host "Applying backup..." -ForegroundColor Yellow
    psql $Env:SUPABASE_DB_URL -f $BackupFile
} finally {
    Pop-Location
}

Write-Host "✅ Restore finished." -ForegroundColor Green
