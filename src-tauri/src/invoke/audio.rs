use tauri::{AppHandle, State};

use crate::utils::audio::AudioPlayer;

fn read_audio_resource(app: &AppHandle, path: &str) -> Result<Vec<u8>, String> {
    crate::utils::crypto::FileAPI::read_resource(app, path, true)
}

#[allow(non_snake_case)]
#[tauri::command]
pub fn playBgm(
    app_handle: AppHandle,
    player: State<'_, AudioPlayer>,
    path: String,
) -> Result<(), String> {
    let bytes = read_audio_resource(&app_handle, &path)?;
    player.play_bgm(bytes)
}

#[allow(non_snake_case)]
#[tauri::command]
pub fn stopBgm(player: State<'_, AudioPlayer>) -> Result<(), String> {
    player.stop_bgm()
}

#[allow(non_snake_case)]
#[tauri::command]
pub fn setBgmVolume(
    player: State<'_, AudioPlayer>,
    volume: f32,
) -> Result<(), String> {
    player.set_bgm_volume(volume)
}

#[allow(non_snake_case)]
#[tauri::command]
pub fn playDialogue(
    app_handle: AppHandle,
    player: State<'_, AudioPlayer>,
    path: String,
) -> Result<(), String> {
    let bytes = read_audio_resource(&app_handle, &path)?;
    player.play_dialogue(bytes)
}

#[allow(non_snake_case)]
#[tauri::command]
pub fn stopDialogue(player: State<'_, AudioPlayer>) -> Result<(), String> {
    player.stop_dialogue()
}

#[allow(non_snake_case)]
#[tauri::command]
pub fn setDialogueVolume(
    player: State<'_, AudioPlayer>,
    volume: f32,
) -> Result<(), String> {
    player.set_dialogue_volume(volume)
}

#[allow(non_snake_case)]
#[tauri::command]
pub fn playSfx(
    app_handle: AppHandle,
    player: State<'_, AudioPlayer>,
    path: String,
) -> Result<(), String> {
    let bytes = read_audio_resource(&app_handle, &path)?;
    player.play_sfx(bytes)
}

#[allow(non_snake_case)]
#[tauri::command]
pub fn stopAllSfx(player: State<'_, AudioPlayer>) -> Result<(), String> {
    player.stop_all_sfx()
}

#[allow(non_snake_case)]
#[tauri::command]
pub fn setSfxVolume(
    player: State<'_, AudioPlayer>,
    volume: f32,
) -> Result<(), String> {
    player.set_sfx_volume(volume)
}
