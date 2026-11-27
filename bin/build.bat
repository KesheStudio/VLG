@echo off
setlocal EnableExtensions EnableDelayedExpansion
rem cmd parses batch files with the console code page active at startup.
rem If it is not 65001, the UTF-8 Chinese text below would be misparsed
rem (lines get split and executed as commands), so relaunch once in a
rem child cmd whose code page is 65001 before the Chinese body is read.
for /f "tokens=2 delims=:." %%A in ('chcp.com') do set "VLG_CP=%%A"
if not "%VLG_CP: =%"=="65001" (
    if not defined VLG_BAT_RELAUNCH (
        set "VLG_BAT_RELAUNCH=1"
        chcp 65001 >nul
        cmd /c call "%~f0" %*
        exit /b !ERRORLEVEL!
    )
)
chcp 65001 >nul
title VLG 一键构建

rem ============================================================
rem  VLG 一键构建脚本（桌面端安装包 / 安卓端 APK）
rem    build.bat                    交互式选择（双击即可）
rem    build.bat desktop            桌面端构建
rem    build.bat android [ABI]      安卓端构建（可选，默认 aarch64）
rem    ABI: aarch64 | armv7 | i686 | x86_64
rem  与 build.ps1 / build.sh 行为一致
rem ============================================================

set "ROOT=%~dp0.."
for %%I in ("%ROOT%") do set "ROOT=%%~fI"
set "MODE="
set "ABI=aarch64"
set "CODE=0"

if "%~1"=="" goto :menu
if /I "%~1"=="desktop" ( set "MODE=desktop" & goto :check_abi )
if /I "%~1"=="android" ( set "MODE=android" & if not "%~2"=="" set "ABI=%~2" & goto :check_abi )
if /I "%~1"=="-h" goto :usage
if /I "%~1"=="--help" goto :usage
if /I "%~1"=="help" goto :usage
echo [ERROR] 未知参数: %~1
echo.
goto :usage

:menu
echo ============================================================
echo   VLG 一键构建
echo ============================================================
echo   1^) 桌面端安装包（Windows，默认）
echo   2^) 安卓端 APK（可选，需要 Android SDK）
echo.
set /p "CHOICE=请输入序号后回车（直接回车 = 1）："
if not defined CHOICE set "CHOICE=1"
if "%CHOICE%"=="1" ( set "MODE=desktop" & goto :check_abi )
if "%CHOICE%"=="2" goto :menu_android
echo [ERROR] 无效的选择: %CHOICE%
set "CODE=1"
goto :done

:menu_android
set "MODE=android"
echo   目标架构说明：
echo     aarch64  真机（绝大多数手机）
echo     armv7    老一些的手机
echo     x86_64   Android Studio 模拟器
echo     i686     32 位模拟器
set /p "ABI=请输入 ABI（直接回车 = aarch64）："
if not defined ABI set "ABI=aarch64"
goto :check_abi

:check_abi
if /I "%MODE%"=="android" (
    if /I not "%ABI%"=="aarch64" if /I not "%ABI%"=="armv7" if /I not "%ABI%"=="i686" if /I not "%ABI%"=="x86_64" (
        echo [ERROR] 不支持的 ABI: %ABI%
        echo   可选值：aarch64（真机）、armv7、i686、x86_64（模拟器）
        set "CODE=1"
        goto :done
    )
)

:start
echo.
if /I "%MODE%"=="desktop" ( echo 本次任务：桌面端构建（Windows 安装包） ) else ( echo 本次任务：安卓端构建 APK，ABI=%ABI% )
echo 项目目录：%ROOT%
echo 说明：脚本会先编译打包器、重新加密资源并同步模板，再调用 Tauri 构建。

echo.
echo [检查] 基础环境：make / npm / cargo
call :check_common
if errorlevel 1 ( set "CODE=1" & goto :done )

if /I "%MODE%"=="android" (
    echo [检查] 安卓环境：SDK / NDK / JDK / 符号链接
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
    echo [3/3] 构建桌面端安装包（首次构建可能较慢）...
    call npm run tauri build
    set "CODE=!ERRORLEVEL!"
    echo.
    if "!CODE!"=="0" (
        echo [DONE] 桌面端构建完成。
        echo   产物目录：%ROOT%\src-tauri\target\release\bundle\
        echo   其中 msi\ 为 MSI 安装包，nsis\ 为 EXE 安装包。
    ) else (
        echo [ERROR] 桌面端构建失败，退出码 !CODE!。
        echo   1^) 提示资源缺失/解密失败：确认第 1、2 步成功，必要时重新运行本脚本。
        echo   2^) 提示缺少 WebView2 或系统组件：按日志提示安装后重试。
        echo   3^) 提示文件被占用：关闭正在运行的应用或杀毒软件后重试。
    )
    goto :done
)

echo [3/3] 构建安卓端 APK（ABI: %ABI%）...
if /I "%ABI%"=="aarch64" ( set "ABI_DIR=arm64-v8a" & set "TRIPLE=aarch64-linux-android" )
if /I "%ABI%"=="armv7" ( set "ABI_DIR=armeabi-v7a" & set "TRIPLE=armv7-linux-androideabi" )
if /I "%ABI%"=="i686" ( set "ABI_DIR=x86" & set "TRIPLE=i686-linux-android" )
if /I "%ABI%"=="x86_64" ( set "ABI_DIR=x86_64" & set "TRIPLE=x86_64-linux-android" )
call npm run tauri android build -- --target %ABI% --apk
set "CODE=!ERRORLEVEL!"
echo.
if "!CODE!"=="0" (
    echo [DONE] 安卓端构建完成。
    echo   产物目录：%ROOT%\src-tauri\gen\android\app\build\outputs\apk\
    echo   （子目录为 universal 或对应 ABI 名称，以日志里的 “Finished 1 APK at” 为准）
    echo   安装到已连接设备：^"%SDK%\platform-tools\adb.exe^" install -r ^<apk 文件^>
) else (
    echo [ERROR] 安卓端构建失败，退出码 !CODE!。
    echo   按日志先判断属于哪种情况：
    echo     1^) “Creation symbolic link is not allowed” 或 “Failed to create a symbolic link … 拒绝访问”
    echo        —— 当前终端没有符号链接权限，卡在把 .so 链接进 jniLibs 的步骤。
    echo        替代做法（README 第 9.3 节）：
    echo          cd bin\resEncryption ^&^& make pack
    echo          npm run tauri android build -- --debug --target %ABI% --apk   （会在链接处失败）
    echo          copy /Y "%ROOT%\src-tauri\target\%TRIPLE%\debug\libvlg_lib.so" "%ROOT%\src-tauri\gen\android\app\src\main\jniLibs\%ABI_DIR%\libvlg_lib.so"
    echo          然后按 README 9.3 节用 gradlew 打包（排除 rustBuild 任务），或改用管理员终端重试。
    echo     2^) 缺少 NDK 27.2.12479018 或 JDK 21 —— 见上面 [检查] 阶段的提示。
    echo     3^) 签名失败 —— 确认 src-tauri\gen\android\keystore.properties 存在且字段完整
    echo        （keyAlias / keyPassword / storeFile / storePassword）。
    echo     4^) Gradle 下载依赖失败 —— 检查网络/代理后重试。
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
    echo   请按 README 第 9.3 节的替代流程处理，或改用“以管理员身份运行”的终端重试本脚本。
) else (
    echo   符号链接权限：正常
)
exit /b 0

:usage
echo 用法：
echo   build.bat                   打开交互菜单（双击本文件也可以）
echo   build.bat desktop           桌面端构建（MSI / NSIS 安装包）
echo   build.bat android           安卓端构建 APK（默认 aarch64）
echo   build.bat android x86_64    指定 ABI：aarch64 / armv7 / i686 / x86_64
echo.
echo 两种模式都会先编译打包器并执行 make pack（生成新密钥、加密资源、同步模板），再调用 Tauri 构建。
echo 等价实现：build.ps1（PowerShell）、build.sh（Git Bash / Linux / macOS）。
exit /b 0

:done
echo.
if not "%CODE%"=="0" (
    echo [FAILED] 本次执行未成功，退出码 %CODE%。请按上面的中文提示处理后重试。
)
if "%~1"=="" (
    echo.
    pause
)
exit /b %CODE%
