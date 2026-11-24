# chcp 65001
chcp 65001 2>$null
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8

function Need-Cmd {
    param($cmd)
    if (-not (Get-Command $cmd -ErrorAction SilentlyContinue)) {
        Write-Host "[ERROR] 未检测到 $cmd，请安装相应依赖或检查 PATH" -ForegroundColor Red
        exit 1
    }
}

# 检查命令是否存在
Need-Cmd node
Need-Cmd npm
Need-Cmd rustc
Need-Cmd cargo
Need-Cmd openssl
Need-Cmd make
Need-Cmd gcc
Need-Cmd g++
Need-Cmd pkg-config

# 验证版本
node --version
if ($LASTEXITCODE -ne 0) { Write-Host "[ERROR] node 执行失败" -ForegroundColor Red; exit $LASTEXITCODE }

npm --version
if ($LASTEXITCODE -ne 0) { Write-Host "[ERROR] npm 执行失败" -ForegroundColor Red; exit $LASTEXITCODE }

rustc --version
if ($LASTEXITCODE -ne 0) { Write-Host "[ERROR] rustc 执行失败" -ForegroundColor Red; exit $LASTEXITCODE }

cargo --version
if ($LASTEXITCODE -ne 0) { Write-Host "[ERROR] cargo 执行失败" -ForegroundColor Red; exit $LASTEXITCODE }

openssl version
if ($LASTEXITCODE -ne 0) { Write-Host "[ERROR] openssl 执行失败" -ForegroundColor Red; exit $LASTEXITCODE }

make --version
if ($LASTEXITCODE -ne 0) { Write-Host "[ERROR] make 执行失败" -ForegroundColor Red; exit $LASTEXITCODE }

gcc --version
if ($LASTEXITCODE -ne 0) { Write-Host "[ERROR] gcc 执行失败" -ForegroundColor Red; exit $LASTEXITCODE }

g++ --version
if ($LASTEXITCODE -ne 0) { Write-Host "[ERROR] g++ 执行失败" -ForegroundColor Red; exit $LASTEXITCODE }

pkg-config --version
if ($LASTEXITCODE -ne 0) { Write-Host "[ERROR] pkg-config 执行失败" -ForegroundColor Red; exit $LASTEXITCODE }

Write-Host "环境检查通过，所有必需依赖已安装"

# 可选工具提示
if (Get-Command code -ErrorAction SilentlyContinue) {
    Write-Host "Visual Studio Code 已安装（可选）"
} else {
    Write-Host "Visual Studio Code 未安装（可选，桌面端构建不需要）"
}

if (Get-Command studio -ErrorAction SilentlyContinue -or $env:ANDROID_HOME -or $env:ANDROID_SDK_ROOT) {
    Write-Host "Android Studio / SDK 已检测到（可选）"
} else {
    Write-Host "Android Studio 未安装（仅安卓端打包需要，桌面端可跳过）"
}

exit 0