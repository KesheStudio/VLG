#requires -Version 5.1
<#
  VLG 一键构建脚本（桌面端安装包 / 安卓端 APK）
    .\build.ps1                    交互式选择
    .\build.ps1 desktop            桌面端构建
    .\build.ps1 android [ABI]      安卓端构建（可选，默认 aarch64）
    ABI: aarch64 | armv7 | i686 | x86_64
  与 build.bat / build.sh 行为一致
#>
[CmdletBinding()]
param(
    [Parameter(Position = 0)][string]$Target = '',
    [Parameter(Position = 1)][string]$Abi = 'aarch64'
)

$ErrorActionPreference = 'Continue'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8
try { $Host.UI.RawUI.WindowTitle = 'VLG 一键构建' } catch { }

$Root = Split-Path -Parent $PSScriptRoot
$script:Code = 0
$script:Mode = ''
$script:Interactive = $false

$AbiMap = @{
    'aarch64' = @{ Dir = 'arm64-v8a'; Triple = 'aarch64-linux-android' }
    'armv7'   = @{ Dir = 'armeabi-v7a'; Triple = 'armv7-linux-androideabi' }
    'i686'    = @{ Dir = 'x86'; Triple = 'i686-linux-android' }
    'x86_64'  = @{ Dir = 'x86_64'; Triple = 'x86_64-linux-android' }
}

function Write-Step([string]$Text) {
    Write-Host ''
    Write-Host $Text -ForegroundColor Cyan
}

function Write-Err([string]$Text) {
    Write-Host $Text -ForegroundColor Red
}

function Show-Usage {
    Write-Host '用法：'
    Write-Host '  .\build.ps1                    打开交互菜单'
    Write-Host '  .\build.ps1 desktop            桌面端构建（MSI / NSIS 安装包）'
    Write-Host '  .\build.ps1 android            安卓端构建 APK（默认 aarch64）'
    Write-Host '  .\build.ps1 android x86_64     指定 ABI：aarch64 / armv7 / i686 / x86_64'
    Write-Host ''
    Write-Host '两种模式都会先编译打包器并执行 make pack（生成新密钥、加密资源、同步模板），再调用 Tauri 构建。'
    Write-Host '等价实现：build.bat（CMD）、build.sh（Git Bash / Linux / macOS）。'
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

    if (Test-SymlinkPermission) {
        Write-Host '  符号链接权限：正常'
    } else {
        Write-Host '[提示] 预先创建测试符号链接失败（当前终端可能不允许创建符号链接）。' -ForegroundColor Yellow
        Write-Host '  Tauri 打包 .so 时会创建符号链接；没有权限时可能直接失败，也可能退回复制。'
        Write-Host '  若构建最终报 “Creation symbolic link is not allowed” 或 “Failed to create a symbolic link … 拒绝访问”，'
        Write-Host '  请按 README 第 9.3 节的替代流程处理，或改用“以管理员身份运行”的 PowerShell 重试本脚本。'
    }

    return @{ Ok = $true; Sdk = $sdk }
}

# ---------- 解析参数 ----------

if ($Target -eq '') {
    $script:Interactive = $true
    Write-Host '============================================================'
    Write-Host '  VLG 一键构建'
    Write-Host '============================================================'
    Write-Host '  1) 桌面端安装包（Windows，默认）'
    Write-Host '  2) 安卓端 APK（可选，需要 Android SDK）'
    Write-Host ''
    $choice = Read-Line '请输入序号后回车（直接回车 = 1）：'
    if ([string]::IsNullOrWhiteSpace($choice)) { $choice = '1' }
    switch ($choice.Trim()) {
        '1' { $Target = 'desktop' }
        '2' {
            $Target = 'android'
            Write-Host '  目标架构说明：'
            Write-Host '    aarch64  真机（绝大多数手机）'
            Write-Host '    armv7    老一些的手机'
            Write-Host '    x86_64   Android Studio 模拟器'
            Write-Host '    i686     32 位模拟器'
            $inputAbi = Read-Line '请输入 ABI（直接回车 = aarch64）：'
            if (-not [string]::IsNullOrWhiteSpace($inputAbi)) { $Abi = $inputAbi.Trim() }
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

if ($Target -eq 'android') {
    $script:Mode = 'android'
    if (-not $AbiMap.ContainsKey($Abi)) {
        Write-Err "[ERROR] 不支持的 ABI：$Abi"
        Write-Host '  可选值：aarch64（真机）、armv7、i686、x86_64（模拟器）'
        exit 1
    }
} else {
    $script:Mode = 'desktop'
}

Write-Host ''
if ($script:Mode -eq 'desktop') {
    Write-Host '本次任务：桌面端构建（Windows 安装包）'
} else {
    Write-Host "本次任务：安卓端构建 APK，ABI=$Abi"
}
Write-Host "项目目录：$Root"
Write-Host '说明：脚本会先编译打包器、重新加密资源并同步模板，再调用 Tauri 构建。'

# ---------- 环境检查 ----------

Write-Step '[检查] 基础环境：make / npm / cargo'
if (-not (Test-CommonEnvironment)) { $script:Code = 1 }

if ($script:Code -eq 0 -and $script:Mode -eq 'android') {
    Write-Host '[检查] 安卓环境：SDK / NDK / JDK / 符号链接'
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

# ---------- 3/3 构建 ----------

if ($script:Code -eq 0) {
    Push-Location $Root
    try {
        if ($script:Mode -eq 'desktop') {
            Write-Step '[3/3] 构建桌面端安装包（首次构建可能较慢）...'
            & npm run tauri build
            $script:Code = $LASTEXITCODE
            Write-Host ''
            if ($script:Code -eq 0) {
                Write-Host '[DONE] 桌面端构建完成。' -ForegroundColor Green
                Write-Host "  产物目录：$(Join-Path $Root 'src-tauri\target\release\bundle')"
                Write-Host '  其中 msi\ 为 MSI 安装包，nsis\ 为 EXE 安装包。'
            } else {
                Write-Err "[ERROR] 桌面端构建失败，退出码 $($script:Code)。"
                Write-Host '  1) 提示资源缺失/解密失败：确认第 1、2 步成功，必要时重新运行本脚本。'
                Write-Host '  2) 提示缺少 WebView2 或系统组件：按日志提示安装后重试。'
                Write-Host '  3) 提示文件被占用：关闭正在运行的应用或杀毒软件后重试。'
            }
        } else {
            $info = $AbiMap[$Abi]
            Write-Step "[3/3] 构建安卓端 APK（ABI: $Abi）..."
            & npm run tauri android build -- --target $Abi --apk
            $script:Code = $LASTEXITCODE
            Write-Host ''
            if ($script:Code -eq 0) {
                Write-Host '[DONE] 安卓端构建完成。' -ForegroundColor Green
                Write-Host "  产物目录：$(Join-Path $Root 'src-tauri\gen\android\app\build\outputs\apk')"
                Write-Host '  （子目录为 universal 或对应 ABI 名称，以日志里的 “Finished 1 APK at” 为准）'
                Write-Host "  安装到已连接设备：& `"$(Join-Path $android.Sdk 'platform-tools\adb.exe')`" install -r <apk 文件>"
            } else {
                Write-Err "[ERROR] 安卓端构建失败，退出码 $($script:Code)。"
                Write-Host '  按日志先判断属于哪种情况：'
                Write-Host '    1) “Creation symbolic link is not allowed” 或 “Failed to create a symbolic link … 拒绝访问”'
                Write-Host '       —— 当前终端没有符号链接权限，卡在把 .so 链接进 jniLibs 的步骤。'
                Write-Host '       替代做法（README 第 9.3 节）：'
                Write-Host '         cd bin/resEncryption; make pack; cd ../..'
                Write-Host "         npm run tauri android build -- --debug --target $Abi --apk   # 会在链接处失败"
                Write-Host "         Copy-Item `"$Root\src-tauri\target\$($info.Triple)\debug\libvlg_lib.so`" `"$Root\src-tauri\gen\android\app\src\main\jniLibs\$($info.Dir)\`" -Force"
                Write-Host '         然后按 README 9.3 节用 gradlew 打包（排除 rustBuild 任务），或改用管理员终端重试。'
                Write-Host '    2) 缺少 NDK 27.2.12479018 或 JDK 21 —— 见上面 [检查] 阶段的提示。'
                Write-Host '    3) 签名失败 —— 确认 src-tauri\gen\android\keystore.properties 存在且字段完整'
                Write-Host '       （keyAlias / keyPassword / storeFile / storePassword）。'
                Write-Host '    4) Gradle 下载依赖失败 —— 检查网络/代理后重试。'
            }
        }
    } finally {
        Pop-Location
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
