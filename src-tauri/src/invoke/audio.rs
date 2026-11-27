use tauri::{AppHandle, State};
use crate::utils::audio::AudioPlayer;

fn read_audio_resource(app: &AppHandle, path: &str) -> Result<Vec<u8>, String> {
    crate::utils::crypto::FileAPI::read_resource(app, path, true)
}

#[allow(non_snake_case)]
#[tauri::command]
pub fn loadBgm(app_handle: AppHandle, player: State<'_, AudioPlayer>, path: String) -> Result<(), String> {
    player.load_bgm(path.clone(), read_audio_resource(&app_handle, &path)?)
}
#[allow(non_snake_case)]
#[tauri::command]
pub fn loadDialogue(app_handle: AppHandle, player: State<'_, AudioPlayer>, path: String) -> Result<(), String> {
    player.load_dialogue(path.clone(), read_audio_resource(&app_handle, &path)?)
}
#[allow(non_snake_case)]
#[tauri::command]
pub fn loadSfx(app_handle: AppHandle, player: State<'_, AudioPlayer>, path: String) -> Result<(), String> {
    player.load_sfx(path.clone(), read_audio_resource(&app_handle, &path)?)
}

#[allow(non_snake_case)]
#[tauri::command]
pub fn playBgm(app_handle: AppHandle, player: State<'_, AudioPlayer>, path: String) -> Result<(), String> {
    let bytes = if player.is_bgm_loaded(&path) { Vec::new() } else { read_audio_resource(&app_handle, &path)? };
    player.play_bgm(path, bytes)
}
#[allow(non_snake_case)]
#[tauri::command]
pub fn stopBgm(player: State<'_, AudioPlayer>) -> Result<(), String> { player.stop_bgm() }
#[allow(non_snake_case)]
#[tauri::command]
pub fn setBgmVolume(player: State<'_, AudioPlayer>, volume: f32) -> Result<(), String> { player.set_bgm_volume(volume) }

#[allow(non_snake_case)]
#[tauri::command]
pub fn playDialogue(app_handle: AppHandle, player: State<'_, AudioPlayer>, path: String) -> Result<(), String> {
    let bytes = if player.is_dialogue_loaded(&path) { Vec::new() } else { read_audio_resource(&app_handle, &path)? };
    player.play_dialogue(path, bytes)
}
#[allow(non_snake_case)]
#[tauri::command]
pub fn stopDialogue(player: State<'_, AudioPlayer>) -> Result<(), String> { player.stop_dialogue() }
#[allow(non_snake_case)]
#[tauri::command]
pub fn setDialogueVolume(player: State<'_, AudioPlayer>, volume: f32) -> Result<(), String> { player.set_dialogue_volume(volume) }

#[allow(non_snake_case)]
#[tauri::command]
pub fn playSfx(app_handle: AppHandle, player: State<'_, AudioPlayer>, path: String) -> Result<(), String> {
    let bytes = if player.is_sfx_loaded(&path) { Vec::new() } else { read_audio_resource(&app_handle, &path)? };
    player.play_sfx(path, bytes)
}
#[allow(non_snake_case)]
#[tauri::command]
pub fn stopAllSfx(player: State<'_, AudioPlayer>) -> Result<(), String> { player.stop_all_sfx() }
#[allow(non_snake_case)]
#[tauri::command]
pub fn setSfxVolume(player: State<'_, AudioPlayer>, volume: f32) -> Result<(), String> { player.set_sfx_volume(volume) }

#[allow(non_snake_case)]
#[tauri::command(rename_all = "camelCase")]
pub fn fadePlayBgm(app_handle: AppHandle, player: State<'_, AudioPlayer>, path: String, time: u64, starting_volume: Option<f32>, target_volume: Option<f32>) -> Result<(), String> {
    let bytes = if player.is_bgm_loaded(&path) { Vec::new() } else { read_audio_resource(&app_handle, &path)? };
    player.fade_play_bgm(path, bytes, time, starting_volume.unwrap_or(0.0), target_volume.unwrap_or(1.0))
}
#[allow(non_snake_case)]
#[tauri::command(rename_all = "camelCase")]
pub fn fadeOutStopBgm(player: State<'_, AudioPlayer>, time: u64, starting_volume: Option<f32>) -> Result<(), String> {
    player.fade_out_stop_bgm(time, starting_volume.unwrap_or(1.0))
}
#[allow(non_snake_case)]
#[tauri::command(rename_all = "camelCase")]
pub fn fadePlayDialogue(app_handle: AppHandle, player: State<'_, AudioPlayer>, path: String, time: u64, starting_volume: Option<f32>, target_volume: Option<f32>) -> Result<(), String> {
    let bytes = if player.is_dialogue_loaded(&path) { Vec::new() } else { read_audio_resource(&app_handle, &path)? };
    player.fade_play_dialogue(path, bytes, time, starting_volume.unwrap_or(0.0), target_volume.unwrap_or(1.0))
}
#[allow(non_snake_case)]
#[tauri::command(rename_all = "camelCase")]
pub fn fadeOutStopDialogue(player: State<'_, AudioPlayer>, time: u64, starting_volume: Option<f32>) -> Result<(), String> {
    player.fade_out_stop_dialogue(time, starting_volume.unwrap_or(1.0))
}
#[allow(non_snake_case)]
#[tauri::command(rename_all = "camelCase")]
pub fn fadePlaySfx(app_handle: AppHandle, player: State<'_, AudioPlayer>, path: String, time: u64, starting_volume: Option<f32>, target_volume: Option<f32>) -> Result<(), String> {
    let bytes = if player.is_sfx_loaded(&path) { Vec::new() } else { read_audio_resource(&app_handle, &path)? };
    player.fade_play_sfx(path, bytes, time, starting_volume.unwrap_or(0.0), target_volume.unwrap_or(1.0))
}

#[allow(non_snake_case)]
#[tauri::command]
pub fn pauseAll(player: State<'_, AudioPlayer>) -> Result<(), String> { player.pause_all() }
#[allow(non_snake_case)]
#[tauri::command]
pub fn resumeAll(player: State<'_, AudioPlayer>) -> Result<(), String> { player.resume_all() }
#[allow(non_snake_case)]
#[tauri::command]
pub fn pauseBgm(player: State<'_, AudioPlayer>) -> Result<(), String> { player.pause_bgm() }
#[allow(non_snake_case)]
#[tauri::command]
pub fn resumeBgm(player: State<'_, AudioPlayer>) -> Result<(), String> { player.resume_bgm() }
#[allow(non_snake_case)]
#[tauri::command]
pub fn pauseDialogue(player: State<'_, AudioPlayer>) -> Result<(), String> { player.pause_dialogue() }
#[allow(non_snake_case)]
#[tauri::command]
pub fn resumeDialogue(player: State<'_, AudioPlayer>) -> Result<(), String> { player.resume_dialogue() }
#[allow(non_snake_case)]
#[tauri::command]
pub fn pauseAllSfx(player: State<'_, AudioPlayer>) -> Result<(), String> { player.pause_all_sfx() }
#[allow(non_snake_case)]
#[tauri::command]
pub fn resumeAllSfx(player: State<'_, AudioPlayer>) -> Result<(), String> { player.resume_all_sfx() }
