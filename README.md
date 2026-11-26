<p align="center">
  <img src="public/logo.png" alt="VLG logo" width="180" />
</p>

<h1 align="center">VLG · Visual Literature Gateway</h1>

<p align="center">基于 Tauri 2 + Vue 3 + RJS（Referenced JSON Script）的视觉小说引擎</p>

---

## 1. 项目简介

VLG 是一个跨平台视觉小说引擎：界面与演出由 Vue 3 负责，资源读取、解密、剧本解析与音频播放由 Rust 侧负责，二者通过 Tauri 2 的 IPC 连接。

引擎支持在构建阶段对图片、音频、视频、剧本等资源做 AES-256-GCM 加密，运行时只在内存中解密，不落地明文。除引擎本身外，仓库还包含资源打包器（`bin/resEncryption`）、RJS 语法高亮插件（`rjs-vscode`）与关卡选择数据结构（`schema`）。

构建目标包括 Windows / macOS / Linux 桌面端，以及 Android（`cn.czgrzx.vlg`）。

## 2. 目录结构

```text
VLG/
├─ src/                        前端（Vue 3 + TypeScript + Vite）
│  ├─ views/                   页面，当前为首页 Home.vue
│  ├─ components/              LevelSelect、UnlockTip 等通用组件
│  ├─ router/                  路由表与关卡解锁守卫
│  ├─ stores/                  Pinia 状态（kv：资源 Blob URL 缓存）
│  ├─ utils/                   FileAPI、audioPlayer、animations、BlobUrl、unlockTip
│  ├─ types/                   配置、MIME、路由 meta 的类型声明
│  ├─ styles/                  全局样式与 SCSS 变量
│  ├─ App.vue / main.ts        应用入口
├─ src-tauri/                  Tauri 2 宿主（Rust）
│  ├─ src/
│  │  ├─ lib.rs                构建 Builder、注册插件/命令/setup
│  │  ├─ main.rs               桌面端入口
│  │  ├─ invoke/               暴露给前端的命令：read、read_rjs、音频控制
│  │  └─ utils/
│  │     ├─ init.rs            启动时读取 config/window.json 并设置窗口
│  │     ├─ audio.rs           rodio 音频播放（BGM / 对白 / 音效）
│  │     ├─ rjs/               RJS 解析器（含 import 解析）
│  │     └─ crypto/            AES-256-GCM 解密、资源读取、key.rs
│  ├─ gen/android/             Android 工程（Tauri CLI 生成，随仓库提交）
│  ├─ build.rs                 构建脚本（Android 目标链接 C++ 运行时）
│  ├─ Cargo.toml               依赖与 release 优化配置
│  └─ tauri.conf.json          窗口、构建、bundle 资源映射
├─ res-dev/                    资源源目录（明文，提交）
├─ res/                        打包器输出（加密/拷贝结果，被 .gitignore 忽略）
├─ bin/
│  ├─ resEncryption/           资源打包器：C++ 工具、Makefile、模板、resources.conf
│  ├─ env.bat / env.cmd / env.ps1 / env.sh   环境自检脚本
│  └─ dev.* / build.*          一键开发 / 构建（.bat、.ps1、.sh 三套等价实现）
├─ public/logo.jpg             项目标识
├─ rjs-vscode/                 RJS 的 VS Code 语法高亮与代码片段插件
├─ schema/                     关卡选择 JSON Schema
├─ index.html / vite.config.ts / package.json / tsconfig*.json
└─ README.md
```

## 3. 架构与模块

### 3.1 前端

- `src/main.ts` 挂载 Vue 应用、Pinia 与路由；`src/App.vue` 作为根组件。
- `src/views/Home.vue` 是首页：读取 `config/settings.json` 与 `config/mainPage.json`，按配置播放 BGM、淡入背景图。
- `src/utils/FileAPI.ts` 是前端访问资源的唯一入口：
  - `read(path, requiresDecrypt = true)` 返回字节数组；
  - `readAsBlobUrl(path, mime?, requiresDecrypt = true)` 返回可直接给 `<img>` / `<audio>` 的 Blob URL；
  - `readRjs(path)` / `readRjsAs<T>(path)` 读取并解析 RJS；
  - `readConfig<T>(path)` 固定以明文方式读取 JSON 配置。
- `src/utils/audioPlayer.ts` 封装 Rust 侧音频命令；`src/utils/BlobUrl.ts` 管理 Blob URL 生命周期；`src/utils/animations.ts` 提供淡入淡出。
- `src/router/index.ts` 定义路由，`meta.requiresUnlock` 为真的路由会先调用后端 `isUnlock` 校验，未解锁时展示提示。

### 3.2 Rust 后端

`src-tauri/src/lib.rs` 完成装配：

- 插件：`tauri-plugin-opener`、`tauri-plugin-fs`（安卓资源读取依赖它）。
- 托管状态：`AudioPlayer`。
- 命令：`read`、`read_rjs` 以及 `playBgm / stopBgm / setBgmVolume`、`playDialogue / stopDialogue / setDialogueVolume`、`playSfx / stopAllSfx / setSfxVolume`。
- `setup`：调用 `utils::init::init`，读取 `config/window.json` 设置标题（桌面端还设置全屏或窗口尺寸）。

### 3.3 资源读取链路

```text
前端 FileAPI.read / readAsBlobUrl / readConfig
  → invoke("read", { path, requiresDecrypt })
  → src-tauri/src/invoke/read.rs
  → src-tauri/src/utils/crypto/FileAPI.rs::read_resource
      1) 校验相对路径（禁止绝对路径与 ".."）
      2) path = resource_dir() / relative_path
      3) read_bytes：Android 走 tauri-plugin-fs，桌面走 std::fs::read
      4) requiresDecrypt 为真时做 AES-256-GCM 解密
```

说明：

- 安卓上 `resource_dir()` 返回 `asset://localhost/` 而非磁盘路径，不能直接 `std::fs::read`，必须经由 fs 插件从 APK 中取流。
- `requiresDecrypt` 由调用方决定，后端不猜测：`config/*`、`saves/*` 为明文，`image/*`、`audio/*`、`video/*`、`level/*`、`text/*` 为密文。

### 3.4 RJS（Referenced JSON Script）

`src-tauri/src/utils/rjs/mod.rs` 实现 RJS 解析：入口文件必须导出 `main` 对象，支持通过 `import` 引用其他 RJS，所有文件都经 `FileAPI` 读取（因此同样支持加密）。解析结果以 JSON 字符串返回前端，由 `FileAPI.readRjsAs<T>` 反序列化。

### 3.5 音频

`src-tauri/src/utils/audio.rs` 基于 rodio 维护 BGM、对白、音效三组播放器，音频字节在内存中解密后直接解码播放，不写临时文件。安卓端 rodio 通过 cpal/oboe 使用 C++ 实现，这一点与 `build.rs` 的链接配置相关，详见第 9.4 节。

## 4. 环境准备

### 4.1 通用依赖

- Node.js 与 npm
- Rust 工具链（rustc、cargo）
- OpenSSL（打包器编译与运行需要）
- GNU Make
- GCC / g++（C++17）
- pkg-config
- Visual Studio Code（推荐）
- Android Studio / Android SDK（仅安卓端需要）

Windows 建议使用 MSYS2/MinGW-w64，并保证 `make`、`g++`、`openssl`、`pkg-config` 在同一个 shell 中可用。打包器的 OpenSSL 细节见 `bin/resEncryption/README.md`。

### 4.2 环境自检

```powershell
# Windows PowerShell
.\bin\env.ps1

# Windows CMD
bin\env.cmd

# Linux / macOS
bash bin/env.sh
```

脚本会逐个检查命令是否存在并输出版本，缺失时给出提示。Android SDK/Studio 为可选项，桌面端可跳过。

### 4.3 安卓额外依赖

```sh
rustup target add aarch64-linux-android armv7-linux-androideabi i686-linux-android x86_64-linux-android
```

此外需要：

- Android SDK，NDK `27.2.12479018`（`build.rs` 依赖其中的 `libc++_shared.so`）；
- JDK 21，`JAVA_HOME` 指向它；
- 用于发布签名的 `src-tauri/gen/android/keystore.properties`（字段 `keyAlias`、`keyPassword`、`storeFile`、`storePassword`）。该文件含密钥信息，不随模板分发，缺失时 release 构建会在 Gradle 配置阶段失败。

## 5. 开发

### 5.1 首次准备

```sh
npm install
```

### 5.2 桌面端开发

```sh
npm run tauri dev
```

Tauri 会按 `beforeDevCommand` 启动 `npm run dev`（Vite 端口 6085），随后打开应用窗口。

注意：应用启动时会读取 `config/window.json` 与首页资源，因此 `res/` 必须存在。首次开发或清缓存后，先执行一次资源打包（见 5.4 或第 8 章），否则会因资源缺失而黑屏。

### 5.3 安卓端开发

```sh
cd bin/resEncryption && make pack
cd ../..
npm run tauri android dev
```

需要已连接的设备或已启动的模拟器。

### 5.4 一键脚本（dev / build）

`bin/` 下提供三套等价实现，覆盖不同终端。三者流程一致：编译资源打包器 → `make pack` → 调用 Tauri；不传 `android` 时只处理桌面端。

| 脚本 | 目标终端 | 说明 |
| --- | --- | --- |
| `dev.bat`、`build.bat` | CMD（可双击） | 推荐入口；双击运行带交互菜单，结束前暂停等待按键 |
| `dev.ps1`、`build.ps1` | PowerShell 5.1+ | 无参数时同样进入交互菜单 |
| `dev.sh`、`build.sh` | Git Bash / WSL / Linux / macOS | 通过 `bash bin/dev.sh` 运行 |

**交互菜单**：不带参数运行时，脚本会列出 `1) 桌面端（默认）`、`2) 安卓端`，直接回车即桌面端；选安卓后还会询问目标设备（真机序列号或模拟器 AVD 名称，构建时为目标 ABI），再次回车使用默认值。所有提示为中文。

**带参数运行**（跳过菜单）：

```bat
bin\dev.bat                       :: 打开菜单
bin\dev.bat desktop               :: 桌面端开发
bin\dev.bat android               :: 安卓端开发（自动选择唯一在线设备）
bin\dev.bat android Medium_Phone_API_37.0 :: 指定模拟器（AVD 名称）；真机填 adb devices 第一列的序列号
bin\build.bat desktop             :: 桌面端构建（MSI / NSIS）
bin\build.bat android             :: 安卓端构建，默认 aarch64（真机）
bin\build.bat android x86_64      :: 安卓端构建，模拟器架构
bin\build.bat --help              :: 查看用法
```

```powershell
.\bin\dev.ps1 desktop
.\bin\build.ps1 android x86_64
```

```sh
bash bin/dev.sh desktop
bash bin/build.sh android aarch64
```

脚本执行的三步：

1. 在 `bin/resEncryption` 执行 `make crypto`（编译打包器）；
2. 执行 `make pack`：生成新密钥、加密/拷贝资源、用模板覆盖 `src-tauri` 中被托管的文件；
3. 启动 `npm run tauri dev` / `npm run tauri build`；安卓模式对应 `npm run tauri android dev` / `npm run tauri android build -- --target <ABI> --apk`。

**检查与提示**：

- 缺少 make / npm / cargo / JDK / Android SDK / NDK 时，直接打印"需要装什么、执行哪条命令"的中文提示，并以非 0 退出码结束，不会静默失败；
- 安卓开发模式若没有在线设备，会列出本机已创建的模拟器及启动命令，并提示连接手机后执行 `adb devices`；
- 安卓构建前会试建一次符号链接；没有权限时打印提示，并说明 Tauri 可能退回复制、也可能直接失败，失败时按 9.3 节处理。

**限制**：

- `.sh` 的目标环境是 Git Bash / WSL / Linux / macOS。本次改造只在 Windows 上对它做了静态检查（`bash -n`），**未在 Windows 上实际运行**；Windows 用户请使用 `.bat` 或 `.ps1`。
- 安卓相关步骤是可选分支，仅当参数为 `android` 或在菜单中选择 2 时才执行。
- `.bat` 必须以 CRLF + UTF-8 保存、`.ps1` 以 UTF-8 BOM 保存，否则中文提示可能乱码或 CMD 解析异常。

## 6. 构建与发布

### 6.1 关键时序

```text
资源打包（make pack）
  → 生成新的随机密钥 key.rs
  → 按密钥重新加密 res/image、res/audio、res/video、res/level、res/text
  → 复制明文资源 res/config、res/saves
  → 用模板覆盖 src-tauri 中被托管的文件
构建应用（npm run tauri build / npm run tauri android build）
  → 把 res/ 打入应用资源目录
  → 编译 Rust，运行时用打包时生成的 key.rs 解密
```

**必须先打包、后构建。** `make pack` 每次都会生成新密钥并重加密资源；若先构建再打包，应用内的密钥与资源不匹配，表现为解密失败、黑屏或图片/音频损坏。出现这种情况时，按上述顺序重新执行一遍即可。

### 6.2 桌面端

```sh
cd bin/resEncryption
make pack
cd ../..
npm run tauri build
```

等价的一键方式：`bin\build.bat`（PowerShell 用 `bin\build.ps1`，Git Bash / Linux / macOS 用 `bash bin/build.sh`），或在 `bin/resEncryption` 下执行 `make all`（即 `make pack` + `make tauri-build`）。

### 6.3 安卓端

```sh
cd bin/resEncryption
make pack
cd ../..
npm run tauri android build -- --target aarch64 --apk   # 真机
# 模拟器：把 aarch64 换成 x86_64
```

等价的一键方式：`bin\build.bat android aarch64`（PowerShell 为 `.\bin\build.ps1 android aarch64`）。

首次在没有 `src-tauri/gen/android` 的机器上构建，需要先执行 `npm run tauri android init` 生成安卓工程，再执行上面的流程。

### 6.4 构建产物

- 桌面端：`src-tauri/target/release/bundle/`（按平台与安装包类型分目录）。
- 安卓端：`src-tauri/gen/android/app/build/outputs/apk/`（按 ABI 与 debug/release 分目录）。
- 前端静态产物：`dist/`。

### 6.5 安卓工程与定制文件

`src-tauri/gen/android` 由 Tauri CLI 生成并随仓库提交，其中少数文件是我们在默认模板上做的定制：

- `app/src/main/AndroidManifest.xml`：横屏、`singleTask`、`resizeableActivity=false`、FileProvider；
- `app/src/main/java/cn/czgrzx/vlg/MainActivity.kt`：强制横屏、沉浸式全屏、刘海屏铺满、屏幕常亮；
- `app/build.gradle.kts`：`tauri-plugin-fs` / `tauri-plugin-opener` 依赖、release 签名读取 `keystore.properties`；
- `app/src/main/jniLibs/**/*.so`：构建时由 Tauri CLI 生成的符号链接，不入库（见 9.4）。

这些定制文件已纳入打包器托管，重新初始化安卓工程后的恢复方式见 9.2。

## 7. 资源与加密

### 7.1 资源目录

源文件位于 `res-dev/`（提交），打包输出到 `res/`（被 `.gitignore` 忽略）。

```text
res-dev/
├─ image/     图片（加密）
├─ audio/     音频（加密）
├─ video/     视频（加密）
├─ level/     剧本与关卡数据（加密）
├─ text/      文本（加密）
├─ config/    配置 JSON（明文拷贝）
└─ saves/     存档模板（明文拷贝）
```

运行时路径以资源根为基准，例如 `image/main.jpg`、`config/window.json`、`level/partOne/level1.rjs`。

### 7.2 加密机制

- 算法：AES-256-GCM，每次 `make pack` 生成一个随机 256 位密钥，全部加密任务共用。
- 文件格式：`NSCR`（4 字节魔数）+ 版本号（1 字节）+ nonce（12 字节）+ tag（16 字节）+ 密文。
- 密钥以 `key.rs` 形式生成到 `src-tauri/src/utils/crypto/key.rs`，拆成四个 `[u8; 8]` 常量，运行时拼装。`key.rs` 是构建产物，不要手工编辑。
- 解密失败（密钥不匹配或文件被篡改）会直接报错，不会返回半成品数据。

需要说明的是：密钥会嵌入客户端二进制，这属于资源混淆而非强保护，不应作为 DRM 使用。

### 7.3 明文与密文约定

| 目录 | 处理方式 | 读取时 `requiresDecrypt` |
| --- | --- | --- |
| `config/` | 明文拷贝 | `false` |
| `saves/` | 明文拷贝 | `false` |
| `image/` `audio/` `video/` `level/` `text/` | 加密 | `true` |

新增资源目录时，需同时更新 `bin/resEncryption/resources.conf` 与第 7.4 节的 bundle 映射。

### 7.4 bundle 资源映射

`src-tauri/tauri.conf.json` 的 `bundle.resources` 决定打包后资源在应用内的位置：

```json
"resources": {
  "../res/image/": "image/",
  "../res/audio/": "audio/",
  "../res/video/": "video/",
  "../res/config/": "config/",
  "../res/level/": "level/",
  "../res/saves/": "saves/",
  "../res/text/": "text/"
}
```

左侧为源目录（相对 `tauri.conf.json`），右侧为应用资源根下的目标目录，必须与前端传入的路径前缀一致。

## 8. 资源打包器（bin/resEncryption）

### 8.1 组成与命令

| 路径 | 作用 |
| --- | --- |
| `tools/crypto.cpp` | 打包器实现：读 manifest、生成密钥、AES-256-GCM 加密、复制模板 |
| `Makefile` | 编译工具、执行打包、调用 Tauri 构建 |
| `resources.conf` | 本项目的任务清单（加密 + 拷贝 + 模板同步） |
| `src-tauri/`、`android/` | 被托管文件的模板副本 |

常用命令（在 `bin/resEncryption` 下执行）：

```sh
make crypto    # 编译 build/crypto(.exe)
make pack      # 生成密钥、加密/拷贝资源、同步模板
make all       # make pack + 桌面端 npm run tauri build
make clean     # 删除 build/、临时密钥与 key.rs
```

若只更新了模板文件、不想换密钥，可以单独用一个只含 `copy` 行的临时 manifest 运行：

```sh
./build/crypto.exe --manifest=copy-only.conf
```

只含 `copy` 任务时工具不会生成新密钥，也不会改动已加密资源。

### 8.2 manifest 语法

每行一个任务，格式 `mode "source" "destination"`，`#` 开头为注释；路径相对执行命令时的当前目录（即 `bin/resEncryption`），支持带空格的引号路径。

- `encrypt "源目录" "目标目录"`：递归加密，输出保持相对目录结构；目标目录会先被清空重建。
- `copy "源目录" "目标目录"`：递归复制，目标目录同样先清空重建。
- `copy "源文件" "目标文件"`：单文件覆盖，只覆盖该文件，不删除任何目录（本项目的模板同步使用此形式）。

`encrypt` 必须使用目录；任何一次运行中只要存在 `encrypt` 任务，就会生成一个新密钥并写入 `key.rs`。

### 8.3 由打包器托管的文件

执行 `make pack` 时，下列文件会被模板覆盖：

| 模板（`bin/resEncryption/` 下） | 覆盖到 |
| --- | --- |
| `src-tauri/src/utils/crypto/`（`decrypt.rs`、`FileAPI.rs`、`mod.rs`、`key.rs`） | `src-tauri/src/utils/crypto/` |
| `src-tauri/build.rs` | `src-tauri/build.rs` |
| `src-tauri/Cargo.toml` | `src-tauri/Cargo.toml` |
| `src-tauri/src/lib.rs` | `src-tauri/src/lib.rs` |
| `android/app/build.gradle.kts` | `src-tauri/gen/android/app/build.gradle.kts` |
| `android/app/src/main/AndroidManifest.xml` | `src-tauri/gen/android/app/src/main/AndroidManifest.xml` |
| `android/app/src/main/java/cn/czgrzx/vlg/MainActivity.kt` | `src-tauri/gen/android/app/src/main/java/cn/czgrzx/vlg/MainActivity.kt` |
| `res-dev/{image,audio,video,level,text}` | 加密后写入 `res/` |
| `res-dev/{config,saves}` | 明文拷贝到 `res/` |

未纳入托管、也无需托管的：

- `src-tauri/gen/android/app/src/main/jniLibs/**/*.so`：构建时由 Tauri CLI 从 NDK 建立符号链接，且已被 `gen/android/app/.gitignore` 忽略，固化进模板反而会带来失效的绝对路径。
- `src-tauri/Cargo.lock`：由 cargo 自动维护。
- `res/`：打包器输出，不入库。
- `src-tauri/gen/android` 下其余文件（Gradle wrapper、`build.gradle.kts`（工程级）、`settings.gradle` 等）：由 CLI 生成，本项目未改动。

### 8.4 修改约定

托管文件是"模板 → 工程"的单向同步，因此：

1. **要改这些文件，先改模板**（`bin/resEncryption/` 下的副本），再执行 `make pack`；直接改工程内文件会在下次打包时被回滚。
2. 新增托管文件时，在 `resources.conf` 追加一行单文件 `copy`，模板路径保持与目标同名结构，例如：

```text
copy "./android/app/src/main/res/xml/file_paths.xml" "../../src-tauri/gen/android/app/src/main/res/xml/file_paths.xml"
```

3. 模板中的目录（如 `src-tauri/src/utils/crypto/`）采用"清空后整体复制"，不要在该目录里放只应存在于工程侧的文件。

### 8.5 一致性校验

改动模板或怀疑同步异常时，可逐文件比对（PowerShell）：

```powershell
$pairs = @(
  @('bin\resEncryption\src-tauri\build.rs', 'src-tauri\build.rs'),
  @('bin\resEncryption\src-tauri\Cargo.toml', 'src-tauri\Cargo.toml'),
  @('bin\resEncryption\src-tauri\src\lib.rs', 'src-tauri\src\lib.rs'),
  @('bin\resEncryption\android\app\build.gradle.kts', 'src-tauri\gen\android\app\build.gradle.kts'),
  @('bin\resEncryption\android\app\src\main\AndroidManifest.xml', 'src-tauri\gen\android\app\src\main\AndroidManifest.xml'),
  @('bin\resEncryption\android\app\src\main\java\cn\czgrzx\vlg\MainActivity.kt', 'src-tauri\gen\android\app\src\main\java\cn\czgrzx\vlg\MainActivity.kt'),
  @('bin\resEncryption\src-tauri\src\utils\crypto\FileAPI.rs', 'src-tauri\src\utils\crypto\FileAPI.rs'),
  @('bin\resEncryption\src-tauri\src\utils\crypto\decrypt.rs', 'src-tauri\src\utils\crypto\decrypt.rs'),
  @('bin\resEncryption\src-tauri\src\utils\crypto\mod.rs', 'src-tauri\src\utils\crypto\mod.rs')
)
foreach ($p in $pairs) {
  if ((Get-FileHash $p[0] -Algorithm MD5).Hash -eq (Get-FileHash $p[1] -Algorithm MD5).Hash) { "SAME  $($p[1])" } else { "DIFF  $($p[1])" }
}
```

`key.rs` 不参与比对：它是每次打包重新生成的产物。

## 9. 注意事项与故障排查

### 9.1 清单速查

| 现象 | 常见原因 | 处理 |
| --- | --- | --- |
| 修改 `Cargo.toml` / `lib.rs` / 安卓文件后，重新打包即丢失 | 只改了工程内文件，未同步模板 | 改模板后重新 `make pack`，见 8.4 |
| 首页黑屏，日志出现 `cannot read resource 'asset://localhost/...'` | 安卓资源读取未走 fs 插件 | 确认 `FileAPI.rs` 的 `read_bytes` 含 android 分支，重新 `make pack` 并构建，见 9.5 |
| 启动即闪退，日志出现 `cannot locate symbol "__cxa_pure_virtual"` | 未链接 C++ 运行时 | 确认 `build.rs` 的链接声明，重新构建，见 9.4 |
| 能启动但资源解密报错 / 图片裂开 | 密钥与资源不是同一次打包产物 | 重新 `make pack` 后再构建，见 6.1 |
| 打包后资源 404 | `bundle.resources` 映射缺失或路径前缀不一致 | 对照 7.4 |
| `openssl/evp.h` 找不到 | 缺少 OpenSSL 开发包 | 安装并配置包管理路径，见 `bin/resEncryption/README.md` |

### 9.2 安卓工程被重新生成后的恢复

`src-tauri/gen/android` 是 CLI 生成目录。以下操作会使其中的定制回到默认模板：

- 删除该目录后重新执行 `npm run tauri android init`；
- 在新机器上首次生成安卓工程；
- 升级 Tauri CLI 后重新初始化工程。

在目录已存在时重复执行 `npm run tauri android init` 不会覆盖现有文件（实测文件内容无变化），因此只有"先删除、后生成"才会真正重置定制。

受影响的定制包括 `AndroidManifest.xml`、`MainActivity.kt`、`app/build.gradle.kts`（本项目的三项主要定制），以及缺失的 `:tauri-plugin-fs` / `:tauri-plugin-opener` 依赖声明。恢复步骤：

```sh
npm run tauri android init          # 仅在目录不存在时需要
cd bin/resEncryption
make pack                           # 用模板覆盖回定制文件
cd ../..
npm run tauri android build -- --target aarch64 --apk
```

注意事项：

- `make pack` 只覆盖文件，不负责重命名包路径。若修改了 `tauri.conf.json` 的 `identifier`，`MainActivity.kt` 的 Kotlin 目录（`java/cn/czgrzx/vlg/`）与 `namespace` 需同步调整，模板路径也要一并改，否则文件会被复制到旧包名下。
- `keystore.properties` 不在托管范围内，重新初始化后需自行恢复，否则 release 构建无法配置签名。
- `android/app/src/main/jniLibs` 无需手工恢复，下一次构建会自动生成。

### 9.3 无符号链接权限时的替代构建

某些终端（受限沙箱、服务账号、未开启开发者模式的非管理员 shell）不允许创建符号链接，`tauri android build` 会在把 `.so` 链接进 `jniLibs` 时失败。此时可让 CLI 先完成 Rust 编译，再手工放置产物由 Gradle 打包（以 x86_64 debug 为例）：

```powershell
npm run build
npm run tauri android build -- --debug --target x86_64 --apk   # 在符号链接处失败，但 .so 已生成
Copy-Item src-tauri\target\x86_64-linux-android\debug\libvlg_lib.so `
  src-tauri\gen\android\app\src\main\jniLibs\x86_64\ -Force
cd src-tauri\gen\android
.\gradlew :app:assembleX86_64Debug -x rustBuildX86_64Debug -x rustBuildUniversalDebug
```

`libc++_shared.so` 同样需要来自 NDK sysroot（`ndk/27.2.12479018/toolchains/llvm/prebuilt/<host>/sysroot/usr/lib/<triple>/libc++_shared.so`）。Release 构建把 `assembleX86_64Debug` 换成 `assembleX86_64Release`，并排除 `rustBuildX86_64Release`、`rustBuildUniversalRelease`。

一键脚本（5.4 节）在进入安卓流程前会试建一次测试符号链接：失败时打印提示并指向本节，但不会自动执行上面的替代流程。

实际表现（本机无符号链接权限时实测）：`build.bat android x86_64` 仍能成功出包；`dev.bat android <模拟器>` 会在链接 `libc++_shared.so` 时失败，日志为 `Failed to create a symbolic link … 拒绝访问 (os error -2147024891)`，脚本随后打印本节指引。需要在安卓上调试时，按上面的替代流程打包并安装后运行，或改用有权限的终端。

### 9.4 启动即闪退：C++ 运行时未链接（已修复）

现象：APK 安装后一打开就退出，logcat 中可见

```text
UnsatisfiedLinkError: dlopen failed: cannot locate symbol "__cxa_pure_virtual"
referenced by lib/x86_64/libvlg_lib.so
```

原因：音频链路 `rodio → cpal → oboe` 的 C++ 实现未把 C++ 运行时链进 cdylib，`libvlg_lib.so` 中的 `__cxa_pure_virtual`、`__gxx_personality_v0` 等符号未定义，而现代 Android 没有 libstdc++ 兜底。

处理方式（已固化在 `src-tauri/build.rs`，并由打包器托管）：

```rust
if std::env::var("CARGO_CFG_TARGET_OS").as_deref() == Ok("android") {
    println!("cargo:rustc-link-lib=dylib=c++_shared");
}
```

这里必须用 `CARGO_CFG_TARGET_OS` 判断目标平台；在 `build.rs` 中写 `#[cfg(target_os = "android")]` 是按宿主平台判断，在 Windows 上永远不生效。

验证：

```powershell
& "$env:ANDROID_SDK_ROOT\ndk\27.2.12479018\toolchains\llvm\prebuilt\windows-x86_64\bin\llvm-readelf.exe" -d `
  src-tauri\target\x86_64-linux-android\release\libvlg_lib.so | Select-String NEEDED

adb logcat -c; adb shell am start -n cn.czgrzx.vlg/.MainActivity
adb logcat -d | Select-String "UnsatisfiedLinkError|cannot locate symbol"
```

第一条命令应出现 `libc++_shared.so`，第二条应无输出。

### 9.5 黑屏、首页不加载：资源读取失败（已修复）

现象：应用启动后纯黑，首页不显示；logcat 中有

```text
Failed to initialize the window: cannot read resource
'asset://localhost/config/window.json': No such file or directory (os error 2)
```

原因：安卓上 `app.path().resource_dir()` 返回 `asset://localhost/`，直接 `std::fs::read` 会得到 ENOENT，所有 bundle 资源都无法读取。

处理方式（已固化在 `src-tauri/src/utils/crypto/FileAPI.rs`）：`read_bytes` 按平台分支，安卓走 `app.fs().read()`（fs 插件会从 APK 取出 asset 并返回文件描述符），桌面端保持 `std::fs::read`；`read_resource(..., should_decrypt)` 的语义不变。

验证：安装后 `adb logcat` 中不再出现 `cannot read resource`；画面先显示启动图、随后显示首页背景。桌面端 `cargo check` 通过、行为不变。

### 9.6 解密失败、黑屏或图片裂开

几乎都是密钥与资源不是同一次打包的产物，例如：先构建、后打包；或清空缓存后只重新构建未重新打包；或手工执行了 `make clean`（会删除 `key.rs`）。处理：

```sh
cd bin/resEncryption
make pack
cd ../..
npm run tauri build        # 或 npm run tauri android build -- --target aarch64 --apk
```

### 9.7 其它

- `resource file not found`：核对 `bundle.resources` 映射与前端传入的路径前缀（第 7.4 节）。
- Rust 报找不到 `key.rs`：先执行 `make pack`。
- 修改 `components` 或 `utils` 后无热更新：确认 Vite 端口 6085 未被占用。
- 打包器编译失败：确认 `make`、`g++`、OpenSSL、`pkg-config` 在同一 shell 内可用。

## 10. 附录

### 10.1 RJS 编辑器支持

`rjs-vscode/` 提供 RJS 的语法高亮、文件图标与代码片段。安装 `rjs-vscode/rjs-language-support-0.1.0.vsix` 即可，或在 VS Code 中通过"从 VSIX 安装"选择该文件。

### 10.2 数据结构

- `schema/levelSelect.schema.json`：关卡选择数据（`res-dev/level/levelSelect.json`）的 JSON Schema，可用于编辑器校验与补全。
- `src/types/`：前端使用的 TypeScript 类型，涵盖配置、MIME 与路由 meta。

### 10.3 相关文档

- `bin/resEncryption/README.md`：资源打包器的正式文档，涵盖清单语法、托管文件、同步约定与一致性校验。
- `src-tauri/tauri.conf.json`：窗口、构建、bundle 配置的唯一来源。
