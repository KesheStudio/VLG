@echo off
setlocal

cd resource-encryption-kit

make crypto
make pack
make tauri-build
@REM  make clean

endlocal