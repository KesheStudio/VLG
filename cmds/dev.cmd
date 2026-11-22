@echo off
setlocal

cd resource-encryption-kit

make crypto
make pack
cd ../..
npm run tauri dev
@REM  make clean

endlocal