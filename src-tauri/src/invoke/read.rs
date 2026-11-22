use tauri::AppHandle;
use crate::utils::crypto::FileAPI;
use crate::utils::rjs;

#[tauri::command(rename_all = "camelCase")]
pub fn read(app: AppHandle, path: String, requires_decrypt: bool) -> Result<Vec<u8>, String> {
    FileAPI::read_resource(&app, &path, requires_decrypt)
}

#[tauri::command(rename_all = "camelCase")]
pub fn read_rjs(app: tauri::AppHandle, path: String) -> Result<String, String> {
    rjs::parse_resource_json(&app, &path)
}