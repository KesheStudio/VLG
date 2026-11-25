# 资源打包器（resEncryption）

`bin/resEncryption` 是 VLG 的资源构建工具：把 `res-dev/` 下的明文资源加密或拷贝到 `res/`，并把工程侧的若干文件用本目录中的模板同步覆盖。

本文只讲打包器本身。项目整体的环境准备、开发与 APK 构建流程见仓库根目录的 [README](../../README.md)。

## 1. 组成

```text
bin/resEncryption/
├─ tools/crypto.cpp            打包器实现（C++17 + OpenSSL）
├─ Makefile                    编译、打包、清理的目标定义
├─ resources.conf              本项目的任务清单
├─ build/                      编译产物（已忽略）
├─ src-tauri/                  工程侧文件的模板副本
│  ├─ build.rs
│  ├─ Cargo.toml
│  ├─ src/lib.rs
│  └─ src/utils/crypto/        decrypt.rs、FileAPI.rs、mod.rs、key.rs
└─ android/                    安卓工程中定制文件的模板副本
   └─ app/
      ├─ build.gradle.kts
      └─ src/main/
         ├─ AndroidManifest.xml
         └─ java/cn/czgrzx/vlg/MainActivity.kt
```

工具职责只有三件事：按清单生成密钥、加密/复制资源、把模板文件覆盖到工程。它不参与前端编译，也不调用 Gradle。

## 2. 一次 `make pack` 做了什么

1. 若 `build/crypto(.exe)` 不存在或源码有更新，先编译工具；
2. 解析 `resources.conf`，若存在 `encrypt` 任务则生成一个随机 256 位密钥：
   - 写入临时文件 `src-tauri/build_key.tmp`；
   - 生成 Rust 密钥文件 `src-tauri/src/utils/crypto/key.rs`（拆成四个 `[u8; 8]` 常量）；
3. 按顺序执行每个任务：
   - `encrypt`：清空目标目录，递归加密源目录，保留相对路径；
   - `copy`（目录）：清空目标目录，递归复制；
   - `copy`（单文件）：直接覆盖目标文件，不删除任何目录；
4. 删除临时密钥文件，结束。

`key.rs` 写在模板目录里，再通过同一次运行中的 `copy ./src-tauri/src/utils/crypto ../../src-tauri/src/utils/crypto` 同步到工程侧，因此工程侧拿到的密钥与本次加密的资源严格对应。

## 3. 命令

所有命令都在 `bin/resEncryption` 目录下执行。

| 命令 | 作用 |
| --- | --- |
| `make crypto` | 只编译 `build/crypto(.exe)` |
| `make pack` | 生成密钥、处理资源、同步模板 |
| `make all` | `make pack` + 桌面端 `npm run tauri build` |
| `make clean` | 删除 `build/`、`src-tauri/build_key.tmp`、模板侧 `key.rs` |
| `make MANIFEST=other.conf pack` | 使用另一份清单 |

Windows 下没有 `make` 时，可用上一级目录的一键脚本：`bin\build.bat` / `bin\dev.bat`（或对应的 `.ps1` / `.sh`），它们同样先进入本目录执行 `make crypto` 与 `make pack`。

### 3.1 直接调用工具

```powershell
# 完整打包（含加密任务时必须提供 key-out / key-tmp）
.\build\crypto.exe --manifest="resources.conf" `
  --key-out="src-tauri/src/utils/crypto/key.rs" `
  --key-tmp="src-tauri/build_key.tmp"
```

参数：

- `--manifest=<path>`：任务清单，必填；
- `--key-out=<path>`：Rust 密钥输出路径，清单中含 `encrypt` 时必填；
- `--key-tmp=<path>`：临时原始密钥路径，含 `encrypt` 时必填，运行结束会删除。

清单中**没有** `encrypt` 任务时，工具不会生成密钥；此时如果仍传了 `--key-out`，它会顺手删除该路径下的旧 `key.rs`（视为过期产物）。这一点在 3.2 节的处理上很关键。

### 3.2 只同步模板，不换密钥

改完模板、只想把文件覆盖到工程侧时，用一份"只有 copy 行"的清单直接运行工具，且**不要传** `--key-out`：

```powershell
Select-String -Path resources.conf -Pattern '^\s*copy\s' |
  ForEach-Object { $_.Line } | Set-Content -Encoding ASCII copy-only.conf
.\build\crypto.exe --manifest="copy-only.conf"
Remove-Item copy-only.conf
```

Linux / macOS：

```sh
grep -E '^\s*copy\s' resources.conf > copy-only.conf
./build/crypto --manifest="copy-only.conf"
rm copy-only.conf
```

这样 `key.rs` 与已加密的 `res/` 都不会被动到。

不要用 `make MANIFEST=copy-only.conf pack` 代替上面的做法：Makefile 总会传 `--key-out`，工具在无加密任务时会删除模板侧 `key.rs`，随后 `crypto/` 目录的整体复制会把工程侧 `key.rs` 一并删掉，导致 Rust 编译找不到密钥。

## 4. `resources.conf` 语法

### 4.1 任务格式

每行一个任务：

```text
mode "source" "destination"
```

- `mode`：`encrypt` 或 `copy`；
- 路径相对**执行命令时的当前目录**（即 `bin/resEncryption`），也接受绝对路径；
- 路径必须加双引号，可包含空格；
- `#` 开头的行与空行被忽略；
- 源路径必须存在，源与目标不能相同；
- 每个任务按书写顺序执行。

### 4.2 目录任务与单文件任务

| 写法 | 行为 |
| --- | --- |
| `encrypt "源目录" "目标目录"` | 递归加密；目标目录先整个删除再重建，源目录的相对结构被保留 |
| `copy "源目录" "目标目录"` | 递归复制；目标目录同样先整个删除再重建 |
| `copy "源文件" "目标文件"` | 单文件覆盖；只写目标文件（必要时创建父目录），不删除任何目录 |

`encrypt` 只接受目录，对单文件使用会报错 `encrypt requires a source directory`。

由于目录任务会清空目标目录，目标目录里不能放"只存在于工程侧、模板里没有"的文件；单文件任务则适合同步零散的工程文件。

### 4.3 密钥规则

- 一次运行最多生成一个密钥，所有 `encrypt` 任务共用；
- 只要清单里出现 `encrypt`，`--key-out` 与 `--key-tmp` 就必须提供；
- 全部为 `copy` 时不生成密钥，也不要求这两个参数。

### 4.4 当前项目的清单

```text
encrypt "../../res-dev/image"  "../../res/image"
encrypt "../../res-dev/audio"  "../../res/audio"
encrypt "../../res-dev/video"  "../../res/video"
encrypt "../../res-dev/level"  "../../res/level"
encrypt "../../res-dev/text"   "../../res/text"

copy "./src-tauri/src/utils/crypto" "../../src-tauri/src/utils/crypto"
copy "../../res-dev/config" "../../res/config"
copy "../../res-dev/saves"   "../../res/saves"

copy "./src-tauri/build.rs"                  "../../src-tauri/build.rs"
copy "./src-tauri/Cargo.toml"                "../../src-tauri/Cargo.toml"
copy "./src-tauri/src/lib.rs"                "../../src-tauri/src/lib.rs"
copy "./android/app/build.gradle.kts"        "../../src-tauri/gen/android/app/build.gradle.kts"
copy "./android/app/src/main/AndroidManifest.xml"                "../../src-tauri/gen/android/app/src/main/AndroidManifest.xml"
copy "./android/app/src/main/java/cn/czgrzx/vlg/MainActivity.kt" "../../src-tauri/gen/android/app/src/main/java/cn/czgrzx/vlg/MainActivity.kt"
```

前半部分是资源处理，后半部分是把工程定制文件同步回 `src-tauri`。

## 5. 托管文件与对应关系

| 模板（`bin/resEncryption/` 下） | 覆盖到（仓库根目录起） | 说明 |
| --- | --- | --- |
| `src-tauri/src/utils/crypto/` | `src-tauri/src/utils/crypto/` | `FileAPI.rs`、`decrypt.rs`、`mod.rs`、`key.rs`；目录整体替换 |
| `src-tauri/build.rs` | `src-tauri/build.rs` | Android 目标链接 `c++_shared` |
| `src-tauri/Cargo.toml` | `src-tauri/Cargo.toml` | 依赖清单 |
| `src-tauri/src/lib.rs` | `src-tauri/src/lib.rs` | 插件注册与命令注册 |
| `android/app/build.gradle.kts` | `src-tauri/gen/android/app/build.gradle.kts` | Gradle 依赖与签名配置 |
| `android/app/src/main/AndroidManifest.xml` | `src-tauri/gen/android/app/src/main/AndroidManifest.xml` | 横屏、启动模式、FileProvider |
| `android/app/src/main/java/cn/czgrzx/vlg/MainActivity.kt` | `src-tauri/gen/android/app/src/main/java/cn/czgrzx/vlg/MainActivity.kt` | 沉浸式横屏 Activity |
| `res-dev/{image,audio,video,level,text}` | `res/{...}` | 加密输出 |
| `res-dev/{config,saves}` | `res/{...}` | 明文拷贝 |

不纳入托管：

- `src-tauri/gen/android/app/src/main/jniLibs/**/*.so`：构建时由 Tauri CLI 生成（`libvlg_lib.so` 指向 `target/<triple>/<profile>/`，`libc++_shared.so` 来自 NDK sysroot），且被 `gen/android/app/.gitignore` 忽略。
- `src-tauri/gen/android/keystore.properties`：含签名口令，被 `.gitignore` 忽略，只存在于本机。
- `src-tauri/Cargo.lock`、`res/`、`build/`：生成物。

## 6. 修改约定

托管关系是单向的：**模板 → 工程**。

1. 需要修改被托管的文件时，先改本目录下的模板，再执行 `make pack`；直接改工程侧文件会在下次打包时被回滚。
2. 新增托管文件时，把模板放到与目标同构的路径下，并在 `resources.conf` 追加单文件任务，例如：

```text
copy "./android/app/src/main/res/xml/file_paths.xml" "../../src-tauri/gen/android/app/src/main/res/xml/file_paths.xml"
```

3. 模板目录（如 `src-tauri/src/utils/crypto/`）采用"整体替换"，不要在该目录内放只应存在于工程侧的文件。
4. `key.rs` 虽然是模板目录中的文件，但它是每次打包的生成物，不要手工编辑，也不要作为固定内容提交到模板版本库（本目录 `.gitignore` 已忽略）。

## 7. 一致性校验

在 `bin/resEncryption` 下执行（PowerShell）：

```powershell
$pairs = @(
 @('src-tauri/build.rs',                '../../src-tauri/build.rs'),
 @('src-tauri/Cargo.toml',              '../../src-tauri/Cargo.toml'),
 @('src-tauri/src/lib.rs',              '../../src-tauri/src/lib.rs'),
 @('android/app/build.gradle.kts',      '../../src-tauri/gen/android/app/build.gradle.kts'),
 @('android/app/src/main/AndroidManifest.xml', '../../src-tauri/gen/android/app/src/main/AndroidManifest.xml'),
 @('android/app/src/main/java/cn/czgrzx/vlg/MainActivity.kt', '../../src-tauri/gen/android/app/src/main/java/cn/czgrzx/vlg/MainActivity.kt'),
 @('src-tauri/src/utils/crypto/FileAPI.rs', '../../src-tauri/src/utils/crypto/FileAPI.rs'),
 @('src-tauri/src/utils/crypto/decrypt.rs', '../../src-tauri/src/utils/crypto/decrypt.rs'),
 @('src-tauri/src/utils/crypto/mod.rs',     '../../src-tauri/src/utils/crypto/mod.rs')
)
foreach ($p in $pairs) {
  if ((Get-FileHash $p[0] -Algorithm MD5).Hash -eq (Get-FileHash $p[1] -Algorithm MD5).Hash) { "SAME  $($p[1])" } else { "DIFF  $($p[1])" }
}
```

全部输出 `SAME` 表示同步状态一致。`key.rs` 不参与比对。

## 8. 常见问题

**解密失败、黑屏或图片损坏**

密钥与资源不是同一次打包的产物。重新执行 `make pack`，再构建应用；不要只重建、不打包。

**改了工程侧文件，重新打包后被还原**

该文件由模板托管，需改模板，见第 6 节。

**删除 `gen/android` 或重新初始化安卓工程后，定制丢失**

Tauri CLI 会按默认模板重建工程，`AndroidManifest.xml`、`MainActivity.kt`、`app/build.gradle.kts` 会回到默认内容。恢复顺序：

```sh
npm run tauri android init     # 仅当 gen/android 不存在
cd bin/resEncryption
make pack
```

`make pack` 会把上表三份文件覆盖回来，`jniLibs` 中的 `.so` 在下次构建时自动重建。需要手工恢复的只有 `keystore.properties`（本机文件，不入库）与任何未纳入托管的自定义。

**构建时报 `Creation symbolic link is not allowed`（Windows）**

当前终端没有创建符号链接的权限，Tauri CLI 在把 `.so` 链接进 `jniLibs` 时失败。处理方式见根目录 README 的"无符号链接权限时的替代构建"。

**`make clean` 之后直接构建**

`make clean` 会删除模板侧的 `key.rs`。构建前必须重新 `make pack`，否则工程侧缺少密钥文件。也不要在 clean 之后用 3.2 节的只同步方式，因为模板里已经没有 `key.rs` 可复制。

**`openssl/evp.h` 找不到 / `pkg-config` 找不到 OpenSSL**

安装 OpenSSL 开发包并确保 `pkg-config` 可见；也可以覆盖 Makefile 变量：

```sh
make OPENSSL_CFLAGS="-IC:/msys64/mingw64/include" OPENSSL_LIBS="-LC:/msys64/mingw64/lib -lssl -lcrypto"
```

**`resource packer error: source does not exist`**

清单里的源路径相对于 `bin/resEncryption`，检查是否漏了 `../../`，或模板目录尚未创建。

**`encrypt requires a source directory`**

对单文件使用了 `encrypt`。单文件只能用 `copy`。
