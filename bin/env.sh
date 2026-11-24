set -eu

need_cmd() {
    if ! command -v "$1" >/dev/null 2>&1; then
        echo "[ERROR] 未检测到 $1，请安装相应依赖或检查 PATH" >&2
        exit 1
    fi
}

need_cmd node
need_cmd npm
need_cmd rustc
need_cmd cargo
need_cmd openssl
need_cmd make
need_cmd gcc
need_cmd g++
need_cmd pkg-config

node --version || { echo "[ERROR] node 执行失败" >&2; exit 1; }
npm --version || { echo "[ERROR] npm 执行失败" >&2; exit 1; }

rustc --version || { echo "[ERROR] rustc 执行失败" >&2; exit 1; }
cargo --version || { echo "[ERROR] cargo 执行失败" >&2; exit 1; }

openssl version || { echo "[ERROR] openssl 执行失败" >&2; exit 1; }

make --version || { echo "[ERROR] make 执行失败" >&2; exit 1; }

gcc --version || { echo "[ERROR] gcc 执行失败" >&2; exit 1; }
g++ --version || { echo "[ERROR] g++ 执行失败" >&2; exit 1; }

pkg-config --version || { echo "[ERROR] pkg-config 执行失败" >&2; exit 1; }

echo "环境检查通过，所有必需依赖已安装"

if command -v code >/dev/null 2>&1; then
    echo "Visual Studio Code 已安装（可选）"
else
    echo "Visual Studio Code 未安装（可选，桌面端构建不需要）"
fi

if command -v studio >/dev/null 2>&1 || [ -n "${ANDROID_HOME:-}" ] || [ -n "${ANDROID_SDK_ROOT:-}" ]; then
    echo "Android Studio / SDK 已检测到（可选）"
else
    echo "Android Studio 未安装（仅安卓端打包需要，桌面端可跳过）"
fi