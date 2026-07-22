# Windows → iOS bulut build (Codemagic = Flutter için Expo EAS)
# Kullanım: powershell -ExecutionPolicy Bypass -File tools\windows_ios_cloud.ps1

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
Set-Location $root

Write-Host ""
Write-Host "KampusteyimAPP — Windows'tan iOS (bulut Mac)" -ForegroundColor Cyan
Write-Host "Expo Flutter IPA uretemez. Codemagic bulut Mac kullanilir." -ForegroundColor Yellow
Write-Host ""
Write-Host "Apple Team ID : 8496F2PR53"
Write-Host "Bundle ID     : com.aystech.mtMobil"
Write-Host "Apple hesap   : alikayracatalkaya321@gmail.com"
Write-Host "Review login  : apple.review@kampusteyim.app / AppleReview2026!"
Write-Host ""

# Git yoksa baslat
if (-not (Test-Path ".git")) {
  Write-Host "[1] Git init..." -ForegroundColor Green
  git init
  git add -A
  git status -sb
  Write-Host "Sonraki: GitHub'da bos repo ac, sonra:" -ForegroundColor Yellow
  Write-Host '  git remote add origin https://github.com/KULLANICI/ayskampus.git'
  Write-Host '  git branch -M main'
  Write-Host '  git commit -m "iOS cloud build ready"'
  Write-Host '  git push -u origin main'
} else {
  Write-Host "[1] Git repo mevcut." -ForegroundColor Green
  git status -sb
}

Write-Host ""
Write-Host "[2] Tarayicida acilacaklar:" -ForegroundColor Green
Write-Host "  - Codemagic: https://codemagic.io/apps"
Write-Host "  - ASC API Key: https://appstoreconnect.apple.com/access/integrations/api"
Write-Host "  - App IDs: https://developer.apple.com/account/resources/identifiers/list"
Write-Host ""

$open = Read-Host "Codemagic + App Store Connect sayfalarini ac? (E/H)"
if ($open -match '^[EeYy]') {
  Start-Process "https://codemagic.io/apps"
  Start-Process "https://appstoreconnect.apple.com/access/integrations/api"
  Start-Process "https://developer.apple.com/account/resources/identifiers/list"
}

Write-Host ""
Write-Host "Codemagic adimlari:" -ForegroundColor Cyan
Write-Host "  1) GitHub ile giris, bu repo'yu ekle"
Write-Host "  2) Teams → Integrations → App Store Connect API Key"
Write-Host "     Integration name: KampusteyimASC  (codemagic.yaml ile ayni)"
Write-Host "  3) App ID com.aystech.mtMobil olustur (Push Notifications ac)"
Write-Host "  4) Workflow: ios-app-store → Start new build"
Write-Host "  5) IPA TestFlight'a gider; App Store'da Submit for Review"
Write-Host ""
