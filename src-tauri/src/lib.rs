mod utils;
mod invoke;

use utils::audio::AudioPlayer;
use utils::init::init;
use invoke::read::{read,read_rjs};
use invoke::audio::{
    playBgm,stopBgm,setBgmVolume,
    playDialogue,stopDialogue,setDialogueVolume,
    playSfx,stopAllSfx,setSfxVolume
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
            playBgm,stopBgm,setBgmVolume,
            playDialogue,stopDialogue,setDialogueVolume,
            playSfx,stopAllSfx,setSfxVolume
        ])
        .setup(|app|{
            if let Err(e) = init(app.handle().clone()) {
                eprintln!("Failed to initialize the window: {}", e);
            }
            Ok(())
        })
        .run(tauri::generate_context!())
        .expect("error while running tauri application");
}
