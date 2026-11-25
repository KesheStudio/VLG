@echo off
chcp 65001 >nul
setlocal EnableExtensions EnableDelayedExpansion
title VLG 一键开发

rem ============================================================
rem  VLG 一键开发脚本（桌面端 / 安卓端）
rem    dev.bat                    交互式选择（双击即可）
rem    dev.bat desktop            桌面端开发
rem    dev.bat android [设备]      安卓端开发（可选）
rem  与 dev.ps1 / dev.sh 行为一致
rem ============================================================

set "ROOT=%~dp0.."
for %%I in ("%ROOT%") do set "ROOT=%%~fI"
set "MODE="
set "DEVICE="
set "CODE=0"

if "%~1"=="" goto :menu
if /I "%~1"=="desktop" ( set "MODE=desktop" & goto :start )
if /I "%~1"=="android" ( set "MODE=android" & set "DEVICE=%~2" & goto :start )
if /I "%~1"=="-h" goto :usage
if /I "%~1"=="--help" goto :usage
if /I "%~1"=="help" goto :usage
echo [ERROR] 未知参数: %~1
echo.
goto :usage

:menu
echo ============================================================
echo   VLG 一键开发
echo ============================================================
echo   1^) 桌面端开发（Windows 窗口，默认）
echo   2^) 安卓端开发（可选，需要已启动的模拟器或已连接手机）
echo.
set /p "CHOICE=请输入序号后回车（直接回车 = 1）："
if not defined CHOICE set "CHOICE=1"
if "%CHOICE%"=="1" ( set "MODE=desktop" & goto :start )
if "%CHOICE%"=="2" goto :menu_android
echo [ERROR] 无效的选择: %CHOICE%
set "CODE=1"
goto :done

:menu_android
set "MODE=android"
set /p "DEVICE=请输入真机序列号或模拟器名称（直接回车 = 自动选择唯一在线设备）："
goto :start

:start
echo.
if /I "%MODE%"=="desktop" ( echo 本次任务：桌面端开发 ) else ( echo 本次任务：安卓端开发 )
echo 项目目录：%ROOT%
echo 说明：脚本会依次编译资源打包器、重新加密资源、再启动开发模式。

echo.
echo [检查] 基础环境：make / npm / cargo
call :check_common
if errorlevel 1 ( set "CODE=1" & goto :done )

if /I "%MODE%"=="android" (
    echo [检查] 安卓环境：SDK / NDK / JDK / 设备 / 符号链接
    call :check_android
    if errorlevel 1 ( set "CODE=1" & goto :done )
)

echo.
echo [1/3] 编译资源打包器（bin\resEncryption）...
pushd "%ROOT%\bin\resEncryption"
call make crypto
if errorlevel 1 (
    popd
    echo [ERROR] 打包器编译失败。
    echo   需要 make、g++（支持 C++17）、OpenSSL 开发包与 pkg-config 在同一终端可用。
    echo   Windows 建议安装 MSYS2（https://www.msys2.org/），装好后执行：
    echo     pacman -S --needed make mingw-w64-ucrt-x86_64-gcc mingw-w64-ucrt-x86_64-openssl mingw-w64-ucrt-x86_64-pkg-config
    echo   并把 C:\msys64\ucrt64\bin 加入 PATH，然后重开终端再运行本脚本。
    set "CODE=1"
    goto :done
)

echo.
echo [2/3] 打包资源并同步模板（每次都会生成新密钥）...
call make pack
if errorlevel 1 (
    popd
    echo [ERROR] 资源打包失败。
    echo   常见原因：res-dev 下缺少目录、OpenSSL 版本不匹配、目标文件被占用。
    echo   详细排查见 bin\resEncryption\README.md 的“常见问题”一节。
    set "CODE=1"
    goto :done
)
popd

echo.
if /I "%MODE%"=="desktop" (
    echo [3/3] 启动桌面端开发模式（Vite 端口 6085）...
    echo   出现应用窗口即表示启动成功；关闭窗口或按 Ctrl+C 结束。
    call npm run tauri dev
) else (
    if defined DEVICE (
        echo [3/3] 启动安卓端开发模式（设备：%DEVICE%）...
        call npm run tauri android dev "%DEVICE%"
    ) else (
        echo [3/3] 启动安卓端开发模式（自动选择在线设备）...
        call npm run tauri android dev
    )
)
set "CODE=!ERRORLEVEL!"

if not "!CODE!"=="0" (
    echo.
    if /I "%MODE%"=="desktop" (
        echo [ERROR] 桌面端开发启动失败，退出码 !CODE!。
        echo   1^) 提示资源缺失/解密失败：第 1、2 步是否成功？可重新运行本脚本。
        echo   2^) 提示端口被占用：关闭占用 6085 端口的程序后重试。
        echo   3^) 提示缺少 WebView2：Windows 10/11 一般自带，缺失时从微软官网安装 WebView2 Runtime。
    ) else (
        echo [ERROR] 安卓端开发失败，退出码 !CODE!。
        echo   1^) 日志出现 “Creation symbolic link is not allowed” 或 “Failed to create a symbolic link … 拒绝访问”：
        echo      当前终端没有创建符号链接的权限，卡在把 .so 链接进 jniLibs 的步骤。
        echo      替代做法见 README 第 9.3 节（手工复制 .so + gradlew 打包），
        echo      或改用“以管理员身份运行”的终端重新执行本脚本。
        echo   2^) 提示找不到设备：先启动模拟器或连接手机（开启 USB 调试），再用 adb devices 确认。
        echo   3^) 缺少 NDK/JDK：按上面 [检查] 阶段的提示安装后重试。
    )
)
goto :done

:check_common
where make >nul 2>&1
if errorlevel 1 (
    echo [ERROR] 未找到 make。
    echo   Windows 请安装 MSYS2（https://www.msys2.org/），装好后执行：
    echo     pacman -S --needed make
    echo   并把 C:\msys64\ucrt64\bin 加入 PATH，重开终端再试。
    exit /b 1
)
where npm >nul 2>&1
if errorlevel 1 (
    echo [ERROR] 未找到 npm。请安装 Node.js LTS（https://nodejs.org/），安装后重开终端。
    exit /b 1
)
where cargo >nul 2>&1
if errorlevel 1 (
    echo [ERROR] 未找到 cargo。请安装 Rust（https://rustup.rs/），安装时选择默认工具链，装完后重开终端。
    exit /b 1
)
echo   OK
exit /b 0

:check_android
call :resolve_sdk
if errorlevel 1 exit /b 1

if not exist "%SDK%\ndk\27.2.12479018" (
    echo [ERROR] 未找到 NDK 27.2.12479018：%SDK%\ndk\27.2.12479018
    echo   打开 Android Studio → SDK Manager → SDK Tools，勾选 “NDK（Side by side）”
    echo   并确保安装的是 27.2.12479018 这个版本。
    exit /b 1
)

if defined JAVA_HOME (
    if not exist "%JAVA_HOME%\bin\java.exe" (
        echo [ERROR] JAVA_HOME 指向的目录下没有 bin\java.exe：%JAVA_HOME%
        echo   请安装 JDK 21（例如 Microsoft Build of OpenJDK），并把 JAVA_HOME 指向安装目录。
        exit /b 1
    )
) else (
    where java >nul 2>&1
    if errorlevel 1 (
        echo [ERROR] 未找到 java。请安装 JDK 21，并设置 JAVA_HOME 环境变量后重开终端。
        exit /b 1
    )
)

if not exist "%SDK%\platform-tools\adb.exe" (
    echo [ERROR] 未找到 adb：%SDK%\platform-tools\adb.exe
    echo   打开 Android Studio → SDK Manager → SDK Tools，勾选 “Android SDK Platform-Tools” 安装。
    exit /b 1
)

"%SDK%\platform-tools\adb.exe" devices | findstr /R /C:"device$" | findstr /V /C:"List of devices" >nul
if errorlevel 1 (
    echo [ERROR] 没有检测到在线的安卓设备。
    if exist "%SDK%\emulator\emulator.exe" (
        echo   本机可用的模拟器：
        "%SDK%\emulator\emulator.exe" -list-avds
        echo   启动其中一个：^"%SDK%\emulator\emulator.exe^" -avd ^<上面的名称^>
    )
    echo   或连接手机：设置 → 关于手机 → 连点“版本号”开启开发者选项 → 打开“USB 调试”，
    echo   然后在手机上允许调试授权，再执行：^"%SDK%\platform-tools\adb.exe^" devices
    echo   设备出现在列表中后，重新运行本脚本。
    exit /b 1
)

call :check_symlink
exit /b 0

:resolve_sdk
set "SDK="
if defined ANDROID_HOME set "SDK=%ANDROID_HOME%"
if not defined SDK if defined ANDROID_SDK_ROOT set "SDK=%ANDROID_SDK_ROOT%"
if not defined SDK if exist "%LOCALAPPDATA%\Android\Sdk" set "SDK=%LOCALAPPDATA%\Android\Sdk"
if not defined SDK (
    echo [ERROR] 未找到 Android SDK。
    echo   请安装 Android Studio，或设置 ANDROID_HOME 指向 SDK 目录（通常为 %%LOCALAPPDATA%%\Android\Sdk）。
    exit /b 1
)
exit /b 0

:check_symlink
powershell -NoProfile -Command "$p=Join-Path $env:TEMP ('vlg-link-test-'+[guid]::NewGuid()); try { New-Item -ItemType SymbolicLink -Path $p -Target $env:TEMP -ErrorAction Stop | Out-Null; Remove-Item $p -Force; exit 0 } catch { exit 1 }" >nul 2>&1
if errorlevel 1 (
    echo [提示] 预先创建测试符号链接失败（当前终端可能不允许创建符号链接）。
    echo   Tauri 在打包 .so 时会自行尝试创建；创建不了会退回复制文件，多数情况下构建仍能完成。
    echo   若构建最终报 “Creation symbolic link is not allowed” 或 “Failed to create a symbolic link … 拒绝访问”，
    echo   说明无法创建符号链接，请按 README 第 9.3 节的替代流程处理。
) else (
    echo   符号链接权限：正常
)
exit /b 0

:usage
echo 用法：
echo   dev.bat                   打开交互菜单（双击本文件也可以）
echo   dev.bat desktop           桌面端开发
echo   dev.bat android           安卓端开发（自动选择唯一在线设备）
echo   dev.bat android ^<目标^>
echo     目标 = 真机序列号（adb devices 第一列）或模拟器名称（emulator -list-avds 输出）
echo     例如：dev.bat android Medium_Phone_API_37.0
echo.
echo 两种模式都会先编译打包器并执行 make pack（生成新密钥、加密资源、同步模板），再启动 Tauri。
echo 等价实现：dev.ps1（PowerShell）、dev.sh（Git Bash / Linux / macOS）。
exit /b 0

:done
echo.
if not "%CODE%"=="0" (
    echo [FAILED] 本次执行未成功，退出码 %CODE%。请按上面的中文提示处理后重试。
) else (
    if /I "%MODE%"=="desktop" (
        if "%~1"=="" echo [DONE] 桌面端开发模式已结束。
    )
)
if "%~1"=="" (
    echo.
    pause
)
exit /b %CODE%
