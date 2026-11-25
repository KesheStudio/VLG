#requires -Version 5.1
<#
  VLG 一键开发脚本（桌面端 / 安卓端）
    .\dev.ps1                    交互式选择
    .\dev.ps1 desktop            桌面端开发
    .\dev.ps1 android [设备]      安卓端开发（可选）
  与 dev.bat / dev.sh 行为一致
#>
[CmdletBinding()]
param(
    [Parameter(Position = 0)][string]$Target = '',
    [Parameter(Position = 1)][string]$Device = ''
)

$ErrorActionPreference = 'Continue'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8
try { $Host.UI.RawUI.WindowTitle = 'VLG 一键开发' } catch { }

$Root = Split-Path -Parent $PSScriptRoot
$script:Code = 0
$script:Mode = ''
$script:Interactive = $false

function Write-Step([string]$Text) {
    Write-Host ''
    Write-Host $Text -ForegroundColor Cyan
}

function Write-Err([string]$Text) {
    Write-Host $Text -ForegroundColor Red
}

function Show-Usage {
    Write-Host '用法：'
    Write-Host '  .\dev.ps1                    打开交互菜单'
    Write-Host '  .\dev.ps1 desktop            桌面端开发'
    Write-Host '  .\dev.ps1 android            安卓端开发（自动选择唯一在线设备）'
    Write-Host '  .\dev.ps1 android <目标>      真机序列号或模拟器名称，例如 Medium_Phone_API_37.0'
    Write-Host ''
    Write-Host '两种模式都会先编译打包器并执行 make pack（生成新密钥、加密资源、同步模板），再启动 Tauri。'
    Write-Host '等价实现：dev.bat（CMD）、dev.sh（Git Bash / Linux / macOS）。'
}

function Test-CommandExists([string]$Name) {
    return [bool](Get-Command $Name -ErrorAction SilentlyContinue)
}

function Read-Line([string]$Prompt) {
    Write-Host $Prompt -NoNewline
    $value = [Console]::ReadLine()
    if ($null -eq $value) { $value = '' }
    return $value
}

function Resolve-AndroidSdk {
    if ($env:ANDROID_HOME) { return $env:ANDROID_HOME }
    if ($env:ANDROID_SDK_ROOT) { return $env:ANDROID_SDK_ROOT }
    $default = Join-Path $env:LOCALAPPDATA 'Android\Sdk'
    if (Test-Path $default) { return $default }
    return ''
}

function Test-SymlinkPermission {
    $probe = Join-Path $env:TEMP ('vlg-link-test-' + [guid]::NewGuid())
    try {
        New-Item -ItemType SymbolicLink -Path $probe -Target $env:TEMP -ErrorAction Stop | Out-Null
        Remove-Item $probe -Force
        return $true
    } catch {
        return $false
    }
}

function Test-CommonEnvironment {
    if (-not (Test-CommandExists 'make')) {
        Write-Err '[ERROR] 未找到 make。'
        Write-Host '  Windows 请安装 MSYS2（https://www.msys2.org/），装好后执行：'
        Write-Host '    pacman -S --needed make'
        Write-Host '  并把 C:\msys64\ucrt64\bin 加入 PATH，重开终端再试。'
        return $false
    }
    if (-not (Test-CommandExists 'npm')) {
        Write-Err '[ERROR] 未找到 npm。请安装 Node.js LTS（https://nodejs.org/），安装后重开终端。'
        return $false
    }
    if (-not (Test-CommandExists 'cargo')) {
        Write-Err '[ERROR] 未找到 cargo。请安装 Rust（https://rustup.rs/），安装时选择默认工具链，装完后重开终端。'
        return $false
    }
    Write-Host '  OK'
    return $true
}

function Test-AndroidEnvironment {
    $sdk = Resolve-AndroidSdk
    if (-not $sdk) {
        Write-Err '[ERROR] 未找到 Android SDK。'
        Write-Host '  请安装 Android Studio，或设置 ANDROID_HOME 指向 SDK 目录（通常为 %LOCALAPPDATA%\Android\Sdk）。'
        return @{ Ok = $false; Sdk = '' }
    }

    $ndk = Join-Path $sdk 'ndk\27.2.12479018'
    if (-not (Test-Path $ndk)) {
        Write-Err "[ERROR] 未找到 NDK 27.2.12479018：$ndk"
        Write-Host '  打开 Android Studio → SDK Manager → SDK Tools，勾选 “NDK（Side by side）”'
        Write-Host '  并确保安装的是 27.2.12479018 这个版本。'
        return @{ Ok = $false; Sdk = $sdk }
    }

    if ($env:JAVA_HOME) {
        if (-not (Test-Path (Join-Path $env:JAVA_HOME 'bin\java.exe'))) {
            Write-Err "[ERROR] JAVA_HOME 指向的目录下没有 bin\java.exe：$env:JAVA_HOME"
            Write-Host '  请安装 JDK 21（例如 Microsoft Build of OpenJDK），并把 JAVA_HOME 指向安装目录。'
            return @{ Ok = $false; Sdk = $sdk }
        }
    } elseif (-not (Test-CommandExists 'java')) {
        Write-Err '[ERROR] 未找到 java。请安装 JDK 21，并设置 JAVA_HOME 环境变量后重开终端。'
        return @{ Ok = $false; Sdk = $sdk }
    }

    $adb = Join-Path $sdk 'platform-tools\adb.exe'
    if (-not (Test-Path $adb)) {
        Write-Err "[ERROR] 未找到 adb：$adb"
        Write-Host '  打开 Android Studio → SDK Manager → SDK Tools，勾选 “Android SDK Platform-Tools” 安装。'
        return @{ Ok = $false; Sdk = $sdk }
    }

    $online = @(& $adb devices 2>$null | Where-Object { $_ -match '\sdevice$' })
    if ($online.Count -eq 0) {
        Write-Err '[ERROR] 没有检测到在线的安卓设备。'
        $emu = Join-Path $sdk 'emulator\emulator.exe'
        if (Test-Path $emu) {
            Write-Host '  本机可用的模拟器：'
            $avds = @(& $emu -list-avds 2>$null | Where-Object { $_ -and $_.Trim() -ne '' })
            if ($avds.Count -gt 0) {
                $avds | ForEach-Object { Write-Host "    $_" }
                Write-Host "  启动其中一个：& `"$emu`" -avd <上面的名称>"
            } else {
                Write-Host '    （没有已创建的模拟器，可在 Android Studio Device Manager 中创建）'
            }
        }
        Write-Host '  或连接手机：设置 → 关于手机 → 连点“版本号”开启开发者选项 → 打开“USB 调试”，'
        Write-Host '  在手机上允许调试授权，然后执行：'
        Write-Host "    & `"$adb`" devices"
        Write-Host '  设备出现在列表中后，重新运行本脚本。'
        return @{ Ok = $false; Sdk = $sdk }
    }

    if (Test-SymlinkPermission) {
        Write-Host '  符号链接权限：正常'
    } else {
        Write-Host '[提示] 预先创建测试符号链接失败（当前终端可能不允许创建符号链接）。' -ForegroundColor Yellow
        Write-Host '  Tauri 打包 .so 时会创建符号链接；没有权限时可能直接失败（安卓 dev 常见），也可能退回复制。'
        Write-Host '  若构建最终报 “Creation symbolic link is not allowed” 或 “Failed to create a symbolic link … 拒绝访问”，'
        Write-Host '  说明无法创建符号链接，请按 README 第 9.3 节的替代流程处理。'
    }

    return @{ Ok = $true; Sdk = $sdk; Adb = $adb }
}

# ---------- 解析参数 ----------

if ($Target -eq '') {
    $script:Interactive = $true
    Write-Host '============================================================'
    Write-Host '  VLG 一键开发'
    Write-Host '============================================================'
    Write-Host '  1) 桌面端开发（Windows 窗口，默认）'
    Write-Host '  2) 安卓端开发（可选，需要已启动的模拟器或已连接手机）'
    Write-Host ''
    $choice = Read-Line '请输入序号后回车（直接回车 = 1）：'
    if ([string]::IsNullOrWhiteSpace($choice)) { $choice = '1' }
    switch ($choice.Trim()) {
        '1' { $Target = 'desktop' }
        '2' {
            $Target = 'android'
            $Device = Read-Line '请输入真机序列号或模拟器名称（直接回车 = 自动选择唯一在线设备）：'
        }
        default {
            Write-Err "[ERROR] 无效的选择：$choice"
            if ($script:Interactive) { Read-Line '按回车键关闭窗口...' | Out-Null }
            exit 1
        }
    }
} elseif ($Target -in @('-h', '--help', 'help')) {
    Show-Usage
    exit 0
} elseif ($Target -notin @('desktop', 'android')) {
    Write-Err "[ERROR] 未知参数：$Target"
    Write-Host ''
    Show-Usage
    exit 1
}

if ($Target -eq 'android') { $script:Mode = 'android' } else { $script:Mode = 'desktop' }

Write-Host ''
if ($script:Mode -eq 'desktop') { Write-Host '本次任务：桌面端开发' } else { Write-Host '本次任务：安卓端开发' }
Write-Host "项目目录：$Root"
Write-Host '说明：脚本会依次编译资源打包器、重新加密资源、再启动开发模式。'

# ---------- 环境检查 ----------

Write-Step '[检查] 基础环境：make / npm / cargo'
if (-not (Test-CommonEnvironment)) { $script:Code = 1 }

if ($script:Code -eq 0 -and $script:Mode -eq 'android') {
    Write-Host '[检查] 安卓环境：SDK / NDK / JDK / 设备 / 符号链接'
    $android = Test-AndroidEnvironment
    if (-not $android.Ok) { $script:Code = 1 }
}

# ---------- 1/3 编译打包器 ----------

if ($script:Code -eq 0) {
    Write-Step '[1/3] 编译资源打包器（bin\resEncryption）...'
    Push-Location (Join-Path $Root 'bin\resEncryption')
    try {
        & make crypto
        if ($LASTEXITCODE -ne 0) {
            Write-Err '[ERROR] 打包器编译失败。'
            Write-Host '  需要 make、g++（支持 C++17）、OpenSSL 开发包与 pkg-config 在同一终端可用。'
            Write-Host '  Windows 建议安装 MSYS2（https://www.msys2.org/），装好后执行：'
            Write-Host '    pacman -S --needed make mingw-w64-ucrt-x86_64-gcc mingw-w64-ucrt-x86_64-openssl mingw-w64-ucrt-x86_64-pkg-config'
            Write-Host '  并把 C:\msys64\ucrt64\bin 加入 PATH，然后重开终端再运行本脚本。'
            $script:Code = 1
        }
    } finally {
        Pop-Location
    }
}

# ---------- 2/3 打包资源 ----------

if ($script:Code -eq 0) {
    Write-Step '[2/3] 打包资源并同步模板（每次都会生成新密钥）...'
    Push-Location (Join-Path $Root 'bin\resEncryption')
    try {
        & make pack
        if ($LASTEXITCODE -ne 0) {
            Write-Err '[ERROR] 资源打包失败。'
            Write-Host '  常见原因：res-dev 下缺少目录、OpenSSL 版本不匹配、目标文件被占用。'
            Write-Host '  详细排查见 bin\resEncryption\README.md 的“常见问题”一节。'
            $script:Code = 1
        }
    } finally {
        Pop-Location
    }
}

# ---------- 3/3 启动 ----------

if ($script:Code -eq 0) {
    Push-Location $Root
    try {
        if ($script:Mode -eq 'desktop') {
            Write-Step '[3/3] 启动桌面端开发模式（Vite 端口 6085）...'
            Write-Host '  出现应用窗口即表示启动成功；关闭窗口或按 Ctrl+C 结束。'
            & npm run tauri dev
        } elseif ($Device) {
            Write-Step "[3/3] 启动安卓端开发模式（设备：$Device）..."
            & npm run tauri android dev $Device
        } else {
            Write-Step '[3/3] 启动安卓端开发模式（自动选择在线设备）...'
            & npm run tauri android dev
        }
        $script:Code = $LASTEXITCODE
    } finally {
        Pop-Location
    }

    if ($script:Code -ne 0) {
        Write-Host ''
        if ($script:Mode -eq 'desktop') {
            Write-Err "[ERROR] 桌面端开发启动失败，退出码 $($script:Code)。"
            Write-Host '  1) 提示资源缺失/解密失败：第 1、2 步是否成功？可重新运行本脚本。'
            Write-Host '  2) 提示端口被占用：关闭占用 6085 端口的程序后重试。'
            Write-Host '  3) 提示缺少 WebView2：Windows 10/11 一般自带，缺失时从微软官网安装 WebView2 Runtime。'
        } else {
            Write-Err "[ERROR] 安卓端开发失败，退出码 $($script:Code)。"
            Write-Host '  1) 日志出现 “Creation symbolic link is not allowed” 或 “Failed to create a symbolic link … 拒绝访问”：'
            Write-Host '     当前终端没有创建符号链接的权限，卡在把 .so 链接进 jniLibs 的步骤。'
            Write-Host '     替代做法见 README 第 9.3 节（手工复制 .so + gradlew 打包），或改用“以管理员身份运行”的终端重试。'
            Write-Host '  2) 提示找不到设备：先启动模拟器或连接手机（开启 USB 调试），再用 adb devices 确认。'
            Write-Host '  3) 缺少 NDK/JDK：按上面 [检查] 阶段的提示安装后重试。'
        }
    }
}

if ($script:Code -ne 0) {
    Write-Host ''
    Write-Err "[FAILED] 本次执行未成功，退出码 $($script:Code)。请按上面的中文提示处理后重试。"
}

if ($script:Interactive) {
    Write-Host ''
    Read-Line '按回车键关闭窗口...' | Out-Null
}

exit $script:Code
