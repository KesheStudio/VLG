@echo off
setlocal

cd resEncryption

make crypto
make pack
cd ../..
npm run tauri dev

endlocal