#!/usr/bin/env sh
set -eu

need_cmd() {
    if ! command -v "$1" >/dev/null 2>&1; then
        echo "[ERROR] 未检测到 $1，请安装 Rust 或检查 PATH" >&2
        exit 1
    fi
}

need_cmd rustc
need_cmd cargo

rustc --version || {
    echo "[ERROR] rustc 执行失败" >&2
    exit 1
}

cargo --version || {
    echo "[ERROR] cargo 执行失败" >&2
    exit 1
}

echo "Rust 环境正常"