fn main() {
    // oboe（rodio/cpal 的安卓音频后端）是 C++ 实现，oboe-sys 未把 C++ 运行时链进 cdylib，
    // 导致 libvlg_lib.so 中 __cxa_pure_virtual 等符号未定义、dlopen 失败。
    // 显式依赖 libc++_shared.so（由 jniLibs 随 APK 一起打包）。
    if std::env::var("CARGO_CFG_TARGET_OS").as_deref() == Ok("android") {
        println!("cargo:rustc-link-lib=dylib=c++_shared");
    }

    tauri_build::build()
}
