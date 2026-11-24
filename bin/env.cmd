@echo off
chcp 65001 >nul
setlocal EnableExtensions

where node >nul 2>&1
if errorlevel 1 ( echo [ERROR] node 未找到 & exit /b 1 )
call node --version
if errorlevel 1 ( echo [ERROR] node 执行失败 & exit /b 1 )

where npm >nul 2>&1
if errorlevel 1 ( echo [ERROR] npm 未找到 & exit /b 1 )
call npm --version
if errorlevel 1 ( echo [ERROR] npm 执行失败 & exit /b 1 )

where rustc >nul 2>&1
if errorlevel 1 ( echo [ERROR] rustc 未找到 & exit /b 1 )
call rustc --version
if errorlevel 1 ( echo [ERROR] rustc 执行失败 & exit /b 1 )

where cargo >nul 2>&1
if errorlevel 1 ( echo [ERROR] cargo 未找到 & exit /b 1 )
call cargo --version
if errorlevel 1 ( echo [ERROR] cargo 执行失败 & exit /b 1 )

where openssl >nul 2>&1
if errorlevel 1 ( echo [ERROR] openssl 未找到 & exit /b 1 )
call openssl version
if errorlevel 1 ( echo [ERROR] openssl 执行失败 & exit /b 1 )

where make >nul 2>&1
if errorlevel 1 ( echo [ERROR] make 未找到 & exit /b 1 )
call make --version
if errorlevel 1 ( echo [ERROR] make 执行失败 & exit /b 1 )

where gcc >nul 2>&1
if errorlevel 1 ( echo [ERROR] gcc 未找到 & exit /b 1 )
call gcc --version
if errorlevel 1 ( echo [ERROR] gcc 执行失败 & exit /b 1 )

where g++ >nul 2>&1
if errorlevel 1 ( echo [ERROR] g++ 未找到 & exit /b 1 )
call g++ --version
if errorlevel 1 ( echo [ERROR] g++ 执行失败 & exit /b 1 )

where pkg-config >nul 2>&1
if errorlevel 1 ( echo [ERROR] pkg-config 未找到 & exit /b 1 )
call pkg-config --version
if errorlevel 1 ( echo [ERROR] pkg-config 执行失败 & exit /b 1 )

where code >nul 2>&1
if errorlevel 1 ( echo Visual Studio Code 未安装（可选） ) else ( echo Visual Studio Code 已安装（可选） )

if defined ANDROID_HOME (
    echo Android SDK 已检测到（可选）
) else if defined ANDROID_SDK_ROOT (
    echo Android SDK 已检测到（可选）
) else (
    where studio >nul 2>&1
    if errorlevel 1 (
        if exist "%LOCALAPPDATA%\Android\Sdk" (
            echo Android SDK 已检测到（可选）
        ) else if exist "%ProgramFiles%\Android\Android Studio\bin\studio64.exe" (
            echo Android Studio 已检测到（可选）
        ) else (
            echo Android Studio 未安装（仅安卓端打包需要，桌面端可跳过）
        )
    ) else (
        echo Android Studio 已检测到（可选）
    )
)

exit /b 0