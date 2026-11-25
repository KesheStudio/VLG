#!/usr/bin/env bash
# ============================================================
#  VLG 一键构建脚本（桌面端安装包 / 安卓端 APK）
#    bash bin/build.sh                交互式选择
#    bash bin/build.sh desktop        桌面端构建
#    bash bin/build.sh android [ABI]  安卓端构建（可选，默认 aarch64）
#    ABI: aarch64 | armv7 | i686 | x86_64
#  与 build.bat / build.ps1 行为一致
# ============================================================
set -u

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MODE=""
ABI="aarch64"
CODE=0
INTERACTIVE=0
SDK=""
ADB=""

abi_dir() {
    case "$1" in
        aarch64) printf 'arm64-v8a' ;;
        armv7)   printf 'armeabi-v7a' ;;
        i686)    printf 'x86' ;;
        x86_64)  printf 'x86_64' ;;
        *)       printf '' ;;
    esac
}

abi_triple() {
    case "$1" in
        aarch64) printf 'aarch64-linux-android' ;;
        armv7)   printf 'armv7-linux-androideabi' ;;
        i686)    printf 'i686-linux-android' ;;
        x86_64)  printf 'x86_64-linux-android' ;;
        *)       printf '' ;;
    esac
}

step() { printf '\n%s\n' "$*"; }
say()  { printf '%s\n' "$*"; }
err()  { printf '%s\n' "$*" >&2; }

usage() {
    say "用法："
    say "  bash bin/build.sh                打开交互菜单"
    say "  bash bin/build.sh desktop        桌面端构建（MSI / NSIS 安装包）"
    say "  bash bin/build.sh android        安卓端构建 APK（默认 aarch64）"
    say "  bash bin/build.sh android x86_64 指定 ABI：aarch64 / armv7 / i686 / x86_64"
    say ""
    say "两种模式都会先编译打包器并执行 make pack（生成新密钥、加密资源、同步模板），再调用 Tauri 构建。"
    say "等价实现：build.bat（CMD）、build.ps1（PowerShell）。"
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
        say "  VLG 一键构建"
        say "============================================================"
        say "  1) 桌面端安装包（Windows，默认）"
        say "  2) 安卓端 APK（可选，需要 Android SDK）"
        read -r -p "请输入序号后回车（直接回车 = 1）：" choice
        choice="${choice:-1}"
        case "$choice" in
            1) MODE="desktop" ;;
            2)
                MODE="android"
                say "  目标架构说明："
                say "    aarch64  真机（绝大多数手机）"
                say "    armv7    老一些的手机"
                say "    x86_64   Android Studio 模拟器"
                say "    i686     32 位模拟器"
                read -r -p "请输入 ABI（直接回车 = aarch64）：" input_abi
                if [ -n "$input_abi" ]; then ABI="$input_abi"; fi
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
        if [ -n "${2:-}" ]; then ABI="$2"; fi
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

if [ "$MODE" = "android" ] && [ -z "$(abi_dir "$ABI")" ]; then
    err "[ERROR] 不支持的 ABI：$ABI"
    say "  可选值：aarch64（真机）、armv7、i686、x86_64（模拟器）"
    exit 1
fi

say ""
if [ "$MODE" = "desktop" ]; then
    say "本次任务：桌面端构建（Windows 安装包）"
else
    say "本次任务：安卓端构建 APK，ABI=$ABI"
fi
say "项目目录：$ROOT"
say "说明：脚本会先编译打包器、重新加密资源并同步模板，再调用 Tauri 构建。"

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
    say "[检查] 安卓环境：SDK / NDK / JDK / 符号链接"

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

    if symlink_ok; then
        say "  符号链接权限：正常"
    else
        say "[提示] 预先创建测试符号链接失败（当前终端可能不允许创建符号链接）。"
        say "  Tauri 打包 .so 时会创建符号链接；没有权限时可能直接失败，也可能退回复制。"
        say "  若构建最终报 “Creation symbolic link is not allowed” 或 “Failed to create a symbolic link … 拒绝访问”，"
        say "  请按 README 第 9.3 节的替代流程处理，或改用“以管理员身份运行”的终端重试本脚本。"
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

# ---------- 3/3 构建 ----------

if [ "$MODE" = "desktop" ]; then
    step "[3/3] 构建桌面端安装包（首次构建可能较慢）..."
    ( cd "$ROOT" && npm run tauri build )
    CODE=$?
    say ""
    if [ "$CODE" -eq 0 ]; then
        say "[DONE] 桌面端构建完成。"
        say "  产物目录：$ROOT/src-tauri/target/release/bundle/"
        say "  其中 msi/ 为 MSI 安装包，nsis/ 为 EXE 安装包。"
    else
        err "[ERROR] 桌面端构建失败，退出码 $CODE。"
        say "  1) 提示资源缺失/解密失败：确认第 1、2 步成功，必要时重新运行本脚本。"
        say "  2) 提示缺少 WebView2 或系统组件：按日志提示安装后重试。"
        say "  3) 提示文件被占用：关闭正在运行的应用或杀毒软件后重试。"
    fi
else
    ABI_DIR="$(abi_dir "$ABI")"
    TRIPLE="$(abi_triple "$ABI")"
    step "[3/3] 构建安卓端 APK（ABI: $ABI）..."
    ( cd "$ROOT" && npm run tauri android build -- --target "$ABI" --apk )
    CODE=$?
    say ""
    if [ "$CODE" -eq 0 ]; then
        say "[DONE] 安卓端构建完成。"
        say "  产物目录：$ROOT/src-tauri/gen/android/app/build/outputs/apk/"
        say "  （子目录为 universal 或对应 ABI 名称，以日志里的 “Finished 1 APK at” 为准）"
        say "  安装到已连接设备：adb install -r <apk 文件>"
    else
        err "[ERROR] 安卓端构建失败，退出码 $CODE。"
        say "  按日志先判断属于哪种情况："
        say "    1) “Creation symbolic link is not allowed” 或 “Failed to create a symbolic link … 拒绝访问”"
        say "       —— 当前终端没有符号链接权限，卡在把 .so 链接进 jniLibs 的步骤。"
        say "       替代做法（README 第 9.3 节）："
        say "         npm run tauri android build -- --debug --target $ABI --apk   # 会在链接处失败"
        say "         cp \"$ROOT/src-tauri/target/$TRIPLE/debug/libvlg_lib.so\" \\"
        say "            \"$ROOT/src-tauri/gen/android/app/src/main/jniLibs/$ABI_DIR/\""
        say "         然后按 README 9.3 节用 gradlew 打包（排除 rustBuild 任务），或改用管理员终端重试。"
        say "    2) 缺少 NDK 27.2.12479018 或 JDK 21 —— 见上面 [检查] 阶段的提示。"
        say "    3) 签名失败 —— 确认 src-tauri/gen/android/keystore.properties 存在且字段完整"
        say "       （keyAlias / keyPassword / storeFile / storePassword）。"
        say "    4) Gradle 下载依赖失败 —— 检查网络/代理后重试。"
    fi
fi

if [ "$CODE" -ne 0 ]; then
    say ""
    err "[FAILED] 本次执行未成功，退出码 $CODE。请按上面的中文提示处理后重试。"
fi

if [ "$INTERACTIVE" -eq 1 ]; then
    say ""
    read -r -p "按回车键关闭窗口..." _
fi

exit "$CODE"
