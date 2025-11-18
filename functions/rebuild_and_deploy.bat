@echo off
title Rebuild va Deploy Cloud Functions

echo ===========================================
echo   BUOC 1: Don dep cache NPM...
echo ===========================================
call npm cache clean --force
echo Cache da duoc don dep.
echo.

echo ===========================================
echo   BUOC 2: Xoa thu muc build cu (lib)...
echo ===========================================
call npm run clean:win
echo Thu muc build cu da duoc xoa.
echo.

echo ===========================================
echo   BUOC 3: Cai dat lai cac goi phu thuoc...
echo ===========================================
call npm install
echo Cac goi da duoc cai dat lai.
echo.

echo ===========================================
echo   BUOC 4: Bien dich lai code TypeScript...
echo ===========================================
call npm run build
echo Code da duoc bien dich lai.
echo.

echo ===========================================
echo   BUOC 5: Tien hanh deploy len Firebase...
echo ===========================================
call firebase deploy --only functions
echo.

echo ===========================================
echo           HOAN TAT TAT CA CAC BUOC!
echo ===========================================
echo Nhan phim bat ky de dong cua so nay.
pause