<#
.SYNOPSIS
Create a timestamped backup of the current Supabase database.
#>

$ErrorActionPreference = "Stop"
$ProjectRoot = Split-Path -Parent $PSScriptRoot
$BackupDir = Join-Path $ProjectRoot "db_backups"

# Create backup directory if it doesn't exist
if (-not (Test-Path $BackupDir)) {
    New-Item -ItemType Directory -Force -Path $BackupDir | Out-Null
}

$Timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$BackupFile = Join-Path $BackupDir "backup_$Timestamp.sql"

Write-Host "Backing up database to $BackupFile ..." -ForegroundColor Yellow

Push-Location (Join-Path $ProjectRoot "supabase")
try {
    supabase db dump > $BackupFile
} finally {
    Pop-Location
}

$FileSize = (Get-Item $BackupFile).Length / 1MB
Write-Host "✅ Backup completed: $BackupFile ($([math]::Round($FileSize, 2)) MB)" -ForegroundColor Green
