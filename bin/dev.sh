#!/usr/bin/env bash
# ============================================================
#  VLG 一键开发脚本（桌面端 / 安卓端）
#    bash bin/dev.sh                交互式选择
#    bash bin/dev.sh desktop        桌面端开发
#    bash bin/dev.sh android [设备]  安卓端开发（可选）
#  与 dev.bat / dev.ps1 行为一致
# ============================================================
set -u

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MODE=""
DEVICE=""
CODE=0
INTERACTIVE=0
SDK=""
ADB=""

step()   { printf '\n%s\n' "$*"; }
say()    { printf '%s\n' "$*"; }
err()    { printf '%s\n' "$*" >&2; }
warn()   { printf '%s\n' "$*"; }

usage() {
    say "用法："
    say "  bash bin/dev.sh                打开交互菜单"
    say "  bash bin/dev.sh desktop        桌面端开发"
    say "  bash bin/dev.sh android        安卓端开发（自动选择唯一在线设备）"
    say "  bash bin/dev.sh android <目标>  真机序列号或模拟器名称，例如 Medium_Phone_API_37.0"
    say ""
    say "两种模式都会先编译打包器并执行 make pack（生成新密钥、加密资源、同步模板），再启动 Tauri。"
    say "等价实现：dev.bat（CMD）、dev.ps1（PowerShell）。"
}

to_path() {
    if command -v cygpath >/dev/null 2>&1; then
        cygpath -u "$1"
    else
        printf '%s' "$1"
    fi
}

# ---------- 解析参数 ----------

case "${1:-}" in
    "")
        INTERACTIVE=1
        say "============================================================"
        say "  VLG 一键开发"
        say "============================================================"
        say "  1) 桌面端开发（Windows 窗口，默认）"
        say "  2) 安卓端开发（可选，需要已启动的模拟器或已连接手机）"
        read -r -p "请输入序号后回车（直接回车 = 1）：" choice
        choice="${choice:-1}"
        case "$choice" in
            1) MODE="desktop" ;;
            2)
                MODE="android"
                read -r -p "请输入真机序列号或模拟器名称（直接回车 = 自动选择唯一在线设备）：" DEVICE
                ;;
            *)
                err "[ERROR] 无效的选择：$choice"
                exit 1
                ;;
        esac
        ;;
    desktop)
        MODE="desktop"
        ;;
    android)
        MODE="android"
        DEVICE="${2:-}"
        ;;
    -h|--help|help)
        usage
        exit 0
        ;;
    *)
        err "[ERROR] 未知参数：$1"
        say ""
        usage
        exit 1
        ;;
esac

say ""
if [ "$MODE" = "desktop" ]; then say "本次任务：桌面端开发"; else say "本次任务：安卓端开发"; fi
say "项目目录：$ROOT"
say "说明：脚本会依次编译资源打包器、重新加密资源、再启动开发模式。"

# ---------- 环境检查 ----------

step "[检查] 基础环境：make / npm / cargo"
if ! command -v make >/dev/null 2>&1; then
    err "[ERROR] 未找到 make。"
    say "  Windows 请安装 MSYS2（https://www.msys2.org/），装好后执行："
    say "    pacman -S --needed make"
    say "  并把 C:\\msys64\\ucrt64\\bin 加入 PATH，重开终端再试。"
    exit 1
fi
if ! command -v npm >/dev/null 2>&1; then
    err "[ERROR] 未找到 npm。请安装 Node.js LTS（https://nodejs.org/），安装后重开终端。"
    exit 1
fi
if ! command -v cargo >/dev/null 2>&1; then
    err "[ERROR] 未找到 cargo。请安装 Rust（https://rustup.rs/），安装时选择默认工具链，装完后重开终端。"
    exit 1
fi
say "  OK"

symlink_ok() {
    local probe
    if command -v powershell.exe >/dev/null 2>&1; then
        powershell.exe -NoProfile -Command "\$p=Join-Path \$env:TEMP ('vlg-link-test-'+[guid]::NewGuid()); try { New-Item -ItemType SymbolicLink -Path \$p -Target \$env:TEMP -ErrorAction Stop | Out-Null; Remove-Item \$p -Force; exit 0 } catch { exit 1 }" >/dev/null 2>&1
        return $?
    fi
    probe="$(mktemp -d 2>/dev/null || printf '/tmp')/vlg-link-test-$$"
    if ln -s "$ROOT" "$probe" 2>/dev/null; then
        if [ -L "$probe" ]; then rm -f "$probe"; return 0; fi
        rm -f "$probe"
        return 1
    fi
    return 1
}

if [ "$MODE" = "android" ]; then
    say "[检查] 安卓环境：SDK / NDK / JDK / 设备 / 符号链接"

    if [ -n "${ANDROID_HOME:-}" ]; then
        SDK="$(to_path "$ANDROID_HOME")"
    elif [ -n "${ANDROID_SDK_ROOT:-}" ]; then
        SDK="$(to_path "$ANDROID_SDK_ROOT")"
    elif [ -n "${LOCALAPPDATA:-}" ] && [ -d "$(to_path "$LOCALAPPDATA")/Android/Sdk" ]; then
        SDK="$(to_path "$LOCALAPPDATA")/Android/Sdk"
    fi
    if [ -z "$SDK" ]; then
        err "[ERROR] 未找到 Android SDK。"
        say "  请安装 Android Studio，或设置 ANDROID_HOME 指向 SDK 目录（通常为 %LOCALAPPDATA%\\Android\\Sdk）。"
        exit 1
    fi

    if [ ! -d "$SDK/ndk/27.2.12479018" ]; then
        err "[ERROR] 未找到 NDK 27.2.12479018：$SDK/ndk/27.2.12479018"
        say "  打开 Android Studio → SDK Manager → SDK Tools，勾选 “NDK (Side by side)”"
        say "  并确保安装的是 27.2.12479018 这个版本。"
        exit 1
    fi

    if [ -n "${JAVA_HOME:-}" ]; then
        if [ ! -x "$(to_path "$JAVA_HOME")/bin/java" ] && [ ! -x "$(to_path "$JAVA_HOME")/bin/java.exe" ]; then
            err "[ERROR] JAVA_HOME 指向的目录下没有 bin/java：$JAVA_HOME"
            say "  请安装 JDK 21（例如 Microsoft Build of OpenJDK），并把 JAVA_HOME 指向安装目录。"
            exit 1
        fi
    elif ! command -v java >/dev/null 2>&1; then
        err "[ERROR] 未找到 java。请安装 JDK 21，并设置 JAVA_HOME 环境变量后重开终端。"
        exit 1
    fi

    if command -v adb >/dev/null 2>&1; then
        ADB="adb"
    elif [ -x "$SDK/platform-tools/adb" ]; then
        ADB="$SDK/platform-tools/adb"
    elif [ -x "$SDK/platform-tools/adb.exe" ]; then
        ADB="$SDK/platform-tools/adb.exe"
    else
        err "[ERROR] 未找到 adb：$SDK/platform-tools/adb"
        say "  打开 Android Studio → SDK Manager → SDK Tools，勾选 “Android SDK Platform-Tools” 安装。"
        exit 1
    fi

    devices="$("$ADB" devices 2>/dev/null | awk 'NR>1 && $2=="device" {print $1}')"
    if [ -z "$devices" ]; then
        err "[ERROR] 没有检测到在线的安卓设备。"
        if [ -x "$SDK/emulator/emulator" ] || [ -x "$SDK/emulator/emulator.exe" ]; then
            emu="$SDK/emulator/emulator"
            [ -x "$emu" ] || emu="$SDK/emulator/emulator.exe"
            say "  本机可用的模拟器："
            "$emu" -list-avds 2>/dev/null | sed 's/^/    /'
            say "  启动其中一个：\"$emu\" -avd <上面的名称>"
        fi
        say "  或连接手机：设置 → 关于手机 → 连点“版本号”开启开发者选项 → 打开“USB 调试”，"
        say "  在手机上允许调试授权，然后执行："
        say "    \"$ADB\" devices"
        say "  设备出现在列表中后，重新运行本脚本。"
        exit 1
    fi

    if symlink_ok; then
        say "  符号链接权限：正常"
    else
        warn "[提示] 预先创建测试符号链接失败（当前终端可能不允许创建符号链接）。"
        warn "  Tauri 打包 .so 时会创建符号链接；没有权限时可能直接失败（安卓 dev 常见），也可能退回复制。"
        warn "  若构建最终报 “Creation symbolic link is not allowed” 或 “Failed to create a symbolic link … 拒绝访问”，"
        warn "  说明无法创建符号链接，请按 README 第 9.3 节的替代流程处理。"
    fi
fi

# ---------- 1/3 编译打包器 ----------

step "[1/3] 编译资源打包器（bin/resEncryption）..."
( cd "$ROOT/bin/resEncryption" && make crypto )
CODE=$?
if [ "$CODE" -ne 0 ]; then
    err "[ERROR] 打包器编译失败。"
    say "  需要 make、g++（支持 C++17）、OpenSSL 开发包与 pkg-config 在同一终端可用。"
    say "  Windows 建议安装 MSYS2（https://www.msys2.org/），装好后执行："
    say "    pacman -S --needed make mingw-w64-ucrt-x86_64-gcc mingw-w64-ucrt-x86_64-openssl mingw-w64-ucrt-x86_64-pkg-config"
    say "  并把 C:\\msys64\\ucrt64\\bin 加入 PATH，然后重开终端再运行本脚本。"
    exit 1
fi

# ---------- 2/3 打包资源 ----------

step "[2/3] 打包资源并同步模板（每次都会生成新密钥）..."
( cd "$ROOT/bin/resEncryption" && make pack )
CODE=$?
if [ "$CODE" -ne 0 ]; then
    err "[ERROR] 资源打包失败。"
    say "  常见原因：res-dev 下缺少目录、OpenSSL 版本不匹配、目标文件被占用。"
    say "  详细排查见 bin/resEncryption/README.md 的“常见问题”一节。"
    exit 1
fi

# ---------- 3/3 启动 ----------

if [ "$MODE" = "desktop" ]; then
    step "[3/3] 启动桌面端开发模式（Vite 端口 6085）..."
    say "  出现应用窗口即表示启动成功；关闭窗口或按 Ctrl+C 结束。"
    ( cd "$ROOT" && npm run tauri dev )
    CODE=$?
else
    if [ -n "$DEVICE" ]; then
        step "[3/3] 启动安卓端开发模式（设备：$DEVICE）..."
        ( cd "$ROOT" && npm run tauri android dev "$DEVICE" )
        CODE=$?
    else
        step "[3/3] 启动安卓端开发模式（自动选择在线设备）..."
        ( cd "$ROOT" && npm run tauri android dev )
        CODE=$?
    fi
fi

if [ "$CODE" -ne 0 ]; then
    say ""
    if [ "$MODE" = "desktop" ]; then
        err "[ERROR] 桌面端开发启动失败，退出码 $CODE。"
        say "  1) 提示资源缺失/解密失败：第 1、2 步是否成功？可重新运行本脚本。"
        say "  2) 提示端口被占用：关闭占用 6085 端口的程序后重试。"
        say "  3) 提示缺少 WebView2：Windows 10/11 一般自带，缺失时从微软官网安装 WebView2 Runtime。"
    else
        err "[ERROR] 安卓端开发失败，退出码 $CODE。"
        say "  1) 日志出现 “Creation symbolic link is not allowed” 或 “Failed to create a symbolic link … 拒绝访问”："
        say "     当前终端没有创建符号链接的权限，卡在把 .so 链接进 jniLibs 的步骤。"
        say "     替代做法见 README 第 9.3 节（手工复制 .so + gradlew 打包），或改用“以管理员身份运行”的终端重试。"
        say "  2) 提示找不到设备：先启动模拟器或连接手机（开启 USB 调试），再用 adb devices 确认。"
        say "  3) 缺少 NDK/JDK：按上面 [检查] 阶段的提示安装后重试。"
    fi
    say ""
    err "[FAILED] 本次执行未成功，退出码 $CODE。请按上面的中文提示处理后重试。"
fi

if [ "$INTERACTIVE" -eq 1 ]; then
    say ""
    read -r -p "按回车键关闭窗口..." _
fi

exit "$CODE"
