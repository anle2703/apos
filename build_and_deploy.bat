@echo off
cd /d D:\4cash\app_4cash
cmd /k "flutter clean && flutter build web --release && firebase deploy --only hosting"