# ERP System Deployment Script
param(
    [ValidateSet("dev", "staging", "production")]
    [string]$Environment = "production"
)

Write-Host "🚀 Deploying ERP System to $Environment" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan

# 1. Run tests
Write-Host "`n1️⃣ Running tests..." -ForegroundColor Yellow
flutter test
if ($LASTEXITCODE -ne 0) {
    Write-Host "❌ Tests failed! Aborting deployment." -ForegroundColor Red
    exit 1
}
Write-Host "✅ Tests passed." -ForegroundColor Green

# 2. Analyze code
Write-Host "`n2️⃣ Running dart analyze..." -ForegroundColor Yellow
flutter analyze
if ($LASTEXITCODE -ne 0) {
    Write-Host "⚠️  Analyzer found issues. Check output above." -ForegroundColor Yellow
}

# 3. Clean build
Write-Host "`n3️⃣ Cleaning previous build..." -ForegroundColor Yellow
flutter clean

# 4. Get dependencies
Write-Host "`n4️⃣ Getting dependencies..." -ForegroundColor Yellow
flutter pub get

# 5. Build
Write-Host "`n5️⃣ Building for $Environment..." -ForegroundColor Yellow
switch ($Environment) {
    "dev" { flutter build windows --debug }
    "staging" { flutter build windows --profile }
    "production" { flutter build windows --release }
}

if ($LASTEXITCODE -ne 0) {
    Write-Host "❌ Build failed!" -ForegroundColor Red
    exit 1
}

# 6. Create installer (production only)
if ($Environment -eq "production") {
    Write-Host "`n6️⃣ Creating installer..." -ForegroundColor Yellow
    # Requires Inno Setup installed
    & "C:\Program Files (x86)\Inno Setup 6\ISCC.exe" "setup.iss"
    if ($LASTEXITCODE -ne 0) {
        Write-Host "⚠️  Installer creation had issues." -ForegroundColor Yellow
    } else {
        Write-Host "✅ Installer created." -ForegroundColor Green
    }
}

# 7. Deploy migrations (if supabase linked)
Write-Host "`n7️⃣ Applying database migrations..." -ForegroundColor Yellow
supabase db push
if ($LASTEXITCODE -eq 0) {
    Write-Host "✅ Migrations applied." -ForegroundColor Green
} else {
    Write-Host "⚠️  Migration had issues. Apply manually." -ForegroundColor Yellow
}

Write-Host "`n✅ Deployment to $Environment complete!" -ForegroundColor Green
Write-Host "Output: build/windows/runner/Release/" -ForegroundColor Cyan
