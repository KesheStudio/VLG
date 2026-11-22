# chcp 65001
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8
if (-not (Get-Command rustc -ErrorAction SilentlyContinue)) {
    Write-Host "[ERROR] 未检测到 rustc，请安装 Rust 或检查 PATH" -ForegroundColor Red
    exit 1
}

if (-not (Get-Command cargo -ErrorAction SilentlyContinue)) {
    Write-Host "[ERROR] 未检测到 cargo，请安装 Rust 或检查 PATH" -ForegroundColor Red
    exit 1
}

rustc --version
if ($LASTEXITCODE -ne 0) {
    Write-Host "[ERROR] rustc 执行失败" -ForegroundColor Red
    exit $LASTEXITCODE
}

cargo --version
if ($LASTEXITCODE -ne 0) {
    Write-Host "[ERROR] cargo 执行失败" -ForegroundColor Red
    exit $LASTEXITCODE
}

Write-Host "Rust 环境正常"
exit 0
