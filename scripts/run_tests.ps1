# Run all ERP system tests
Write-Host "🧪 Running ERP System Tests" -ForegroundColor Cyan
Write-Host "===========================" -ForegroundColor Cyan

# Set exit code
$exitCode = 0

# Run unit tests
Write-Host "`n📦 Unit Tests" -ForegroundColor Yellow
flutter test test/unit/ --reporter expanded
if ($LASTEXITCODE -ne 0) { $exitCode = 1 }

# Run integration tests
Write-Host "`n🔗 Integration Tests" -ForegroundColor Yellow
flutter test test/integration/ --reporter expanded
if ($LASTEXITCODE -ne 0) { $exitCode = 1 }

# Run workflow tests
Write-Host "`n🔄 Workflow Tests" -ForegroundColor Yellow
flutter test test/workflow/ --reporter expanded
if ($LASTEXITCODE -ne 0) { $exitCode = 1 }

# Run all tests together
Write-Host "`n📋 All Tests" -ForegroundColor Yellow
flutter test --reporter expanded
if ($LASTEXITCODE -ne 0) { $exitCode = 1 }

# Summary
Write-Host "`n===========================" -ForegroundColor Cyan
if ($exitCode -eq 0) {
    Write-Host "✅ All tests passed!" -ForegroundColor Green
} else {
    Write-Host "❌ Some tests failed!" -ForegroundColor Red
}

exit $exitCode
