mod utils;
mod invoke;

#[cfg(mobile)]
use tauri::Manager;
use utils::audio::AudioPlayer;
use utils::init::init;
use invoke::read::{read, read_rjs};
use invoke::audio::{
    loadBgm, loadDialogue, loadSfx,
    playBgm, stopBgm, setBgmVolume,
    playDialogue, stopDialogue, setDialogueVolume,
    playSfx, stopAllSfx, setSfxVolume,
    fadePlayBgm, fadeOutStopBgm,
    fadePlayDialogue, fadeOutStopDialogue,
    fadePlaySfx,
    pauseAll, resumeAll,
    pauseBgm, resumeBgm,
    pauseDialogue, resumeDialogue,
    pauseAllSfx, resumeAllSfx,
};

#[cfg_attr(mobile, tauri::mobile_entry_point)]
pub fn run() {
    #[allow(non_snake_case)]
    let audioPlayers = AudioPlayer::new()
        .expect("failed to initialize encrypted audio player");

    tauri::Builder::default()
        .plugin(tauri_plugin_opener::init())
        .plugin(tauri_plugin_fs::init())
        .manage(audioPlayers)
        .invoke_handler(tauri::generate_handler![
            read, read_rjs,
            loadBgm, loadDialogue, loadSfx,
            playBgm, stopBgm, setBgmVolume,
            playDialogue, stopDialogue, setDialogueVolume,
            playSfx, stopAllSfx, setSfxVolume,
            fadePlayBgm, fadeOutStopBgm,
            fadePlayDialogue, fadeOutStopDialogue,
            fadePlaySfx,
            pauseAll, resumeAll,
            pauseBgm, resumeBgm,
            pauseDialogue, resumeDialogue,
            pauseAllSfx, resumeAllSfx
        ])
        .on_window_event(|_window, _event| {
            #[cfg(mobile)]
            match _event {
                tauri::WindowEvent::Suspended => {
                    if let Err(error) = _window.state::<AudioPlayer>().set_lifecycle_paused(true) {
                        eprintln!("Failed to pause audio on app suspend: {error}");
                    }
                }
                tauri::WindowEvent::Resumed => {
                    if let Err(error) = _window.state::<AudioPlayer>().set_lifecycle_paused(false) {
                        eprintln!("Failed to resume audio on app resume: {error}");
                    }
                }
                _ => {}
            }
        })
        .setup(|app| {
            if let Err(error) = init(app.handle().clone()) {
                eprintln!("Failed to initialize the window: {error}");
            }
            Ok(())
        })
        .run(tauri::generate_context!())
        .expect("error while running tauri application");
}
