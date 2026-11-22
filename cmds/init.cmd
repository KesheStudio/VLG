@echo off
chcp 65001
setlocal

where rustc >nul 2>&1
if errorlevel 1 (
    echo [ERROR] 未检测到 rustc，请安装 Rust 或检查 PATH
    exit /b 1
)

where cargo >nul 2>&1
if errorlevel 1 (
    echo [ERROR] 未检测到 cargo，请安装 Rust 或检查 PATH
    exit /b 1
)

rustc --version
if errorlevel 1 (
    echo [ERROR] rustc 执行失败
    exit /b 1
)

cargo --version
if errorlevel 1 (
    echo [ERROR] cargo 执行失败
    exit /b 1
)

echo Rust 环境正常
exit /b 0