@echo off
echo ========================================================
echo [1/6] DANG DON DEP DU LIEU CU...
call flutter clean

echo [2/6] DANG BUILD FLUTTER WEB (BASE HREF /app/)...
:: QUAN TRỌNG: Dấu / ở cuối "/app/" là bắt buộc
call flutter build web --base-href "/app/" --release

echo [3/6] DANG TAO CAU TRUC THU MUC...
cd build

:: Doi ten thu muc 'web' thanh 'app_temp'
move web app_temp

:: Tao thu muc 'web' moi (thu muc public goc)
mkdir web

:: Di chuyen 'app_temp' vao trong 'web' va doi ten thanh 'app'
move app_temp web\app

echo [4/6] DANG COPY LANDING PAGE VAO...
:: Copy Landing Page tu web_landing vao thu muc goc
xcopy /s /e /y ..\web_landing\* web\

echo [5/6] KIEM TRA LAI...
cd ..
if exist build\web\index.html (
    echo -> Landing Page: OK
) else (
    echo -> LOI: Khong thay Landing Page!
)

if exist build\web\app\index.html (
    echo -> App Flutter: OK
) else (
    echo -> LOI: Khong thay App Flutter!
)

echo [6/6] DANG DEPLOY LEN FIREBASE...
call firebase deploy --only hosting

echo ========================================================
echo HOAN TAT! WEBSITE DA DUOC CAP NHAT.
pause