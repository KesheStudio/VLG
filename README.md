# VLG (Visual Literature Gateway)

> 新一代视觉小说引擎使用***Tauri + VUE3 + RJS(Referenced JSON Script)*** 快速构建一个视觉小说
---

## 注意事项
- 开始使用前请确保已安装以下依赖
- - Node.js npm
- - rustc
- - cargo
- - OpenSSL
- - Make
- - GCC/g++
- - pkg-config
- - Visual Studio Code
- - Android Studio(安卓端打包时会调用配套工具如果是桌面端可不安装)

---

## 安卓端构建

### 前置

- `rustup target add aarch64-linux-android armv7-linux-androideabi i686-linux-android x86_64-linux-android`
- Android SDK + NDK `27.2.12479018`（`build.rs` 依赖它提供的 `libc++_shared.so`）
- JDK 21，`JAVA_HOME` 指向它
- 资源打包器需要 MSYS2/MinGW-w64 的 `make`、`g++`、OpenSSL（详见 `bin/resEncryption/README.md`）

### 关键时序：先跑打包器，再构建 APK

```sh
cd bin/resEncryption
make pack          # 生成 key.rs、加密 res/，并把打包器模板同步回 src-tauri
cd ../..
npm run tauri android build -- --target aarch64 --apk   # 真机用 aarch64，模拟器用 x86_64
```

顺序不能反：`make pack` 每次都会**生成新的随机密钥并重新加密 `res/`**，APK 构建会把 `res/` 打进 `assets`、用 `src-tauri/src/utils/crypto/key.rs` 解密。先构建再打包会导致密钥与资源不匹配，表现为解密失败、黑屏或裂图；这种情况重新执行一次上面的顺序即可。

产物在 `src-tauri/gen/android/app/build/outputs/apk/` 下（按 flavor 与 debug/release 分子目录）。

### 已修复问题一：启动即闪退（C++ 运行时未链接）

现象：APK 安装后一打开就退出，logcat 关键行：

```text
UnsatisfiedLinkError: dlopen failed: cannot locate symbol "__cxa_pure_virtual"
referenced by lib/x86_64/libvlg_lib.so
```

根因：音频链路 `rodio → cpal → oboe` 的 C++ 实现（`oboe-sys`）没有把 C++ 运行时链进 cdylib，`libvlg_lib.so` 里 `__cxa_pure_virtual`、`__gxx_personality_v0` 等符号未定义；现代 Android 没有 libstdc++ 兜底，`System.loadLibrary` 直接失败。

修复与相关文件：

| 文件 | 改动 |
| --- | --- |
| `src-tauri/build.rs` | 目标为 android 时输出 `cargo:rustc-link-lib=dylib=c++_shared` |
| `src-tauri/Cargo.toml` | 新增 `tauri-plugin-fs = "2"` |
| `src-tauri/src/lib.rs` | Builder 链上注册 `.plugin(tauri_plugin_fs::init())` |
| `src-tauri/gen/android/app/build.gradle.kts` | 新增 `implementation(project(":tauri-plugin-fs"))` |
| `src-tauri/src/utils/crypto/FileAPI.rs` | 安卓读取走 fs 插件（见下一节） |

`build.rs` 里必须用运行期环境变量判断目标平台，写成 `#[cfg(target_os = "android")]` 是按**宿主**（Windows）判断，永远不会生效：

```rust
if std::env::var("CARGO_CFG_TARGET_OS").as_deref() == Ok("android") {
    println!("cargo:rustc-link-lib=dylib=c++_shared");
}
```

`gen/android/app/src/main/jniLibs/<abi>/libc++_shared.so` **不需要手工放置、也不要提交**：它被 `gen/android/app/.gitignore` 忽略，构建时 Tauri CLI 会依据 `build.rs` 的链接声明，从 NDK 建立指向 `.../ndk/27.2.12479018/toolchains/llvm/prebuilt/windows-x86_64/sysroot/usr/lib/<triple>/libc++_shared.so` 的符号链接。因此换机器时只要装好 NDK，`npm run tauri android build` 会自动带入。

验证：

```powershell
# 1) 动态依赖里应出现 libc++_shared.so
& "$env:ANDROID_SDK_ROOT\ndk\27.2.12479018\toolchains\llvm\prebuilt\windows-x86_64\bin\llvm-readelf.exe" -d `
  src-tauri\target\x86_64-linux-android\release\libvlg_lib.so | Select-String NEEDED

# 2) 安装后冷启动，日志里不应再有 UnsatisfiedLinkError / cannot locate symbol
adb logcat -c; adb shell am start -n cn.czgrzx.vlg/.MainActivity
adb logcat -d | Select-String "UnsatisfiedLinkError|cannot locate symbol"
```

### 已修复问题二：黑屏、首页不加载（asset:// 读取失败）

现象：启动后纯黑，首页不出现；logcat 关键行：

```text
RustStdoutStderr: Failed to initialize the window: cannot read resource
'asset://localhost/config/window.json': No such file or directory (os error 2)
```

根因：安卓上 `app.path().resource_dir()` 返回的是 `asset://localhost/` 而不是磁盘路径，直接 `std::fs::read` 必然 ENOENT。所有 bundle 资源（`config/*.json`、图片、音频）读不到，前端初始化抛错后停在黑屏。

修复：`FileAPI.rs` 拆出 `read_bytes`，android 分支走 `app.fs().read()`（`tauri-plugin-fs` 的安卓实现会把 APK 内 asset 取出并返回文件描述符），桌面端保持 `std::fs::read`；`read_resource(..., should_decrypt)` 的语义不变，是否解密仍由调用方传入的标记决定（`config/*.json` 为明文，`image/*`、`audio/*`、`.rjs` 解密）。

验证：安装后 `adb logcat` 中不再出现 `cannot read resource`，画面先显示启动图、随后显示首页背景；桌面端 `cargo check` 通过，行为不变。

### 打包器接管的文件（`bin/resEncryption`）

`make pack` 会按 `resources.conf` 把下列模板覆盖到工程内。这些文件自此由打包器接管，**修改时必须同步修改模板**，否则下次打包会被回滚：

| 模板 | 覆盖到 |
| --- | --- |
| `bin/resEncryption/src-tauri/src/utils/crypto/` | `src-tauri/src/utils/crypto/`（`FileAPI.rs`、`decrypt.rs`、`key.rs`、`mod.rs`） |
| `bin/resEncryption/src-tauri/build.rs` | `src-tauri/build.rs` |
| `bin/resEncryption/src-tauri/Cargo.toml` | `src-tauri/Cargo.toml` |
| `bin/resEncryption/src-tauri/src/lib.rs` | `src-tauri/src/lib.rs` |
| `bin/resEncryption/android/app/build.gradle.kts` | `src-tauri/gen/android/app/build.gradle.kts` |
| `bin/resEncryption/res-dev/{image,audio,video,level,text}` | 加密后写入 `res/`（`res/**` 已被 git 忽略） |

打包器的 `copy` 任务现在同时支持目录与单文件（单文件是直接覆盖目标文件，不删除目录）。

未纳入托管、也无需托管的：

- `gen/android/app/src/main/jniLibs/**/*.so`：构建时由 Tauri CLI 生成的符号链接（已被 git 忽略），见上一节。
- `src-tauri/Cargo.lock`：由 cargo 在构建时自动补齐依赖。
- `AndroidManifest.xml` 及 `gen/android` 下其余文件：由 Tauri CLI 生成，本次修复不涉及。
- `res/`：打包器输出，不入库。

### 无符号链接权限时的替代构建

某些 shell（服务账号、受限沙箱、未开开发者模式的非管理员终端）不能创建符号链接，`tauri android build` 会在把 `.so` 链接进 jniLibs 时报 `Creation symbolic link is not allowed`。此时先让 CLI 完成 Rust 编译（报错可忽略），再手工放置产物由 Gradle 打包（以 x86_64 debug 为例）：

```powershell
npm run build
npm run tauri android build -- --debug --target x86_64 --apk   # 会在符号链接处失败，但 .so 已生成
Copy-Item src-tauri\target\x86_64-linux-android\debug\libvlg_lib.so `
  src-tauri\gen\android\app\src\main\jniLibs\x86_64\ -Force
cd src-tauri\gen\android
.\gradlew.bat :app:assembleX86_64Debug -x rustBuildX86_64Debug -x rustBuildUniversalDebug
```

release 同理换成 `assembleX86_64Release` / `rustBuildX86_64Release`，APK 在 `app\build\outputs\apk\x86_64\{debug,release}\`。注意这条路径跳过了 `rustBuild`，不会自动跑前端构建和资源复制，所以必须先 `npm run build`，并且确保 `res/` 已是最新（先 `make pack`）。

