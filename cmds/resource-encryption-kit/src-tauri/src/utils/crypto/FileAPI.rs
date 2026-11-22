use std::path::{Component, Path};

use tauri::{AppHandle, Manager, Runtime};

use super::decrypt;

pub fn read_resource<R: Runtime>(
    app: &AppHandle<R>,
    relative_path: &str,
    should_decrypt: bool,
) -> Result<Vec<u8>, String> {
    let relative = Path::new(relative_path);
    if relative.as_os_str().is_empty()
        || relative.is_absolute()
        || relative.components().any(|c| matches!(c, Component::ParentDir | Component::RootDir | Component::Prefix(_)))
    {
        return Err("resource path must be a non-empty relative path without '..'".into());
    }

    let path = app.path().resource_dir()
        .map_err(|e| format!("cannot resolve Tauri resource directory: {e}"))?
        .join(relative);

    let bytes = std::fs::read(&path)
        .map_err(|e| format!("cannot read resource '{}': {e}", path.display()))?;

    if should_decrypt {
        decrypt::decrypt(&bytes)
    } else {
        Ok(bytes)
    }
}
