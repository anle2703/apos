@echo off
cd /d D:\4cash\app_4cash
cmd /k "flutter build web --release && firebase deploy --only hosting"