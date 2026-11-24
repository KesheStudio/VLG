use serde::Deserialize;
use tauri::{AppHandle, Manager, Runtime};
#[cfg(not(target_os = "android"))]
use tauri::LogicalSize;
use crate::utils::crypto::FileAPI::read_resource;

#[derive(Debug, Clone, Deserialize)]
pub struct WindowConfig {
    #[cfg(not(target_os = "android"))]
    #[serde(rename = "isFullScreen")]
    pub is_full_screen: bool,
    #[cfg(not(target_os = "android"))]
    pub width: u32,
    #[cfg(not(target_os = "android"))]
    pub height: u32,
    pub title: String,
}

fn load_window_config<R: Runtime>(app: &AppHandle<R>) -> Result<WindowConfig, String> {
    let bytes = read_resource(app, "config/window.json", false)?;

    let json_str = String::from_utf8(bytes)
        .map_err(|e| format!("window.json is not valid UTF-8: {}", e))?;

    let config: WindowConfig = serde_json::from_str(&json_str)
        .map_err(|e| format!("Failed to parse window.json: {}", e))?;

    Ok(config)
}

pub fn init<R: Runtime>(app: AppHandle<R>) -> Result<(), String> {
    let config = load_window_config(&app)?;

    let window = app.get_webview_window("main")
        .ok_or_else(|| "Can't find a window labeled 'main'".to_string())?;

    window.set_title(&config.title)
        .map_err(|e| format!("Failed to set window title: {}", e))?;

    #[cfg(not(target_os = "android"))]
    {
        if config.is_full_screen {
            window.set_fullscreen(true)
                .map_err(|e| format!("Failed to set full screen: {}", e))?;
        } else {
            window.set_size(LogicalSize::new(config.width as f64, config.height as f64))
                .map_err(|e| format!("Failed to set window size: {}", e))?;
        }
    }

    Ok(())
}