use std::{
    io::Cursor,
    sync::mpsc::{self, Receiver, Sender},
    thread,
};

use rodio::{Decoder, OutputStream, OutputStreamHandle, Sink, Source};

type Reply = Sender<Result<(), String>>;

enum AudioCommand {
    PlayBgm { bytes: Vec<u8>, reply: Reply },
    StopBgm { reply: Reply },
    SetBgmVolume { volume: f32, reply: Reply },

    PlayDialogue { bytes: Vec<u8>, reply: Reply },
    StopDialogue { reply: Reply },
    SetDialogueVolume { volume: f32, reply: Reply },

    PlaySfx { bytes: Vec<u8>, reply: Reply },
    StopAllSfx { reply: Reply },
    SetSfxVolume { volume: f32, reply: Reply },
}

pub struct AudioPlayer {
    tx: Sender<AudioCommand>,
}

impl AudioPlayer {
    pub fn new() -> Result<Self, String> {
        let (tx, rx) = mpsc::channel::<AudioCommand>();
        let (ready_tx, ready_rx) = mpsc::sync_channel::<Result<(), String>>(1);

        thread::Builder::new()
            .name("encrypted-audio-player".into())
            .spawn(move || {
                let (stream, stream_handle) = match OutputStream::try_default() {
                    Ok(output) => output,
                    Err(error) => {
                        let _ = ready_tx.send(Err(format!(
                            "failed to initialize audio output: {error}"
                        )));
                        return;
                    }
                };

                let _stream = stream;
                if ready_tx.send(Ok(())).is_err() {
                    return;
                }

                run_audio_worker(rx, &stream_handle);
            })
            .map_err(|error| format!("failed to spawn audio worker: {error}"))?;

        ready_rx
            .recv()
            .map_err(|_| "audio worker stopped during initialization".to_string())??;

        Ok(Self { tx })
    }

    fn request(
        &self,
        make_command: impl FnOnce(Reply) -> AudioCommand,
    ) -> Result<(), String> {
        let (reply_tx, reply_rx) = mpsc::channel();
        self.tx
            .send(make_command(reply_tx))
            .map_err(|_| "audio worker is not available".to_string())?;

        reply_rx
            .recv()
            .map_err(|_| "audio worker dropped the command response".to_string())?
    }

    pub fn play_bgm(&self, bytes: Vec<u8>) -> Result<(), String> {
        self.request(|reply| AudioCommand::PlayBgm { bytes, reply })
    }

    pub fn stop_bgm(&self) -> Result<(), String> {
        self.request(|reply| AudioCommand::StopBgm { reply })
    }

    pub fn set_bgm_volume(&self, volume: f32) -> Result<(), String> {
        self.request(|reply| AudioCommand::SetBgmVolume {
            volume: clamp_volume(volume),
            reply,
        })
    }

    pub fn play_dialogue(&self, bytes: Vec<u8>) -> Result<(), String> {
        self.request(|reply| AudioCommand::PlayDialogue { bytes, reply })
    }

    pub fn stop_dialogue(&self) -> Result<(), String> {
        self.request(|reply| AudioCommand::StopDialogue { reply })
    }

    pub fn set_dialogue_volume(&self, volume: f32) -> Result<(), String> {
        self.request(|reply| AudioCommand::SetDialogueVolume {
            volume: clamp_volume(volume),
            reply,
        })
    }

    pub fn play_sfx(&self, bytes: Vec<u8>) -> Result<(), String> {
        self.request(|reply| AudioCommand::PlaySfx { bytes, reply })
    }

    pub fn stop_all_sfx(&self) -> Result<(), String> {
        self.request(|reply| AudioCommand::StopAllSfx { reply })
    }

    pub fn set_sfx_volume(&self, volume: f32) -> Result<(), String> {
        self.request(|reply| AudioCommand::SetSfxVolume {
            volume: clamp_volume(volume),
            reply,
        })
    }
}

fn clamp_volume(volume: f32) -> f32 {
    if volume.is_finite() {
        volume.clamp(0.0, 1.0)
    } else {
        0.0
    }
}

fn create_sink(
    stream_handle: &OutputStreamHandle,
    bytes: Vec<u8>,
    looping: bool,
    volume: f32,
) -> Result<Sink, String> {
    let decoder = Decoder::new(Cursor::new(bytes))
        .map_err(|error| format!("audio decode failed: {error}"))?;
    let sink = Sink::try_new(stream_handle)
        .map_err(|error| format!("failed to create audio sink: {error}"))?;

    if looping {
        sink.append(decoder.repeat_infinite());
    } else {
        sink.append(decoder);
    }

    sink.set_volume(volume);
    sink.play();
    Ok(sink)
}

fn reply(reply: Reply, result: Result<(), String>) {
    let _ = reply.send(result);
}

fn run_audio_worker(rx: Receiver<AudioCommand>, stream_handle: &OutputStreamHandle) {
    let mut bgm_sink: Option<Sink> = None;
    let mut dialogue_sink: Option<Sink> = None;
    let mut sfx_sinks: Vec<Sink> = Vec::new();

    let mut bgm_volume = 1.0_f32;
    let mut dialogue_volume = 1.0_f32;
    let mut sfx_volume = 1.0_f32;

    while let Ok(command) = rx.recv() {
        match command {
            AudioCommand::PlayBgm { bytes, reply: response } => {
                match create_sink(stream_handle, bytes, true, bgm_volume) {
                    Ok(new_sink) => {
                        if let Some(old_sink) = bgm_sink.replace(new_sink) {
                            old_sink.stop();
                        }
                        reply(response, Ok(()));
                    }
                    Err(error) => reply(response, Err(error)),
                }
            }
            AudioCommand::StopBgm { reply: response } => {
                if let Some(sink) = bgm_sink.take() {
                    sink.stop();
                }
                reply(response, Ok(()));
            }
            AudioCommand::SetBgmVolume { volume, reply: response } => {
                bgm_volume = volume;
                if let Some(sink) = &bgm_sink {
                    sink.set_volume(volume);
                }
                reply(response, Ok(()));
            }

            AudioCommand::PlayDialogue { bytes, reply: response } => {
                match create_sink(stream_handle, bytes, false, dialogue_volume) {
                    Ok(new_sink) => {
                        if let Some(old_sink) = dialogue_sink.replace(new_sink) {
                            old_sink.stop();
                        }
                        reply(response, Ok(()));
                    }
                    Err(error) => reply(response, Err(error)),
                }
            }
            AudioCommand::StopDialogue { reply: response } => {
                if let Some(sink) = dialogue_sink.take() {
                    sink.stop();
                }
                reply(response, Ok(()));
            }
            AudioCommand::SetDialogueVolume { volume, reply: response } => {
                dialogue_volume = volume;
                if let Some(sink) = &dialogue_sink {
                    sink.set_volume(volume);
                }
                reply(response, Ok(()));
            }

            AudioCommand::PlaySfx { bytes, reply: response } => {
                sfx_sinks.retain(|sink| !sink.empty());
                match create_sink(stream_handle, bytes, false, sfx_volume) {
                    Ok(sink) => {
                        sfx_sinks.push(sink);
                        reply(response, Ok(()));
                    }
                    Err(error) => reply(response, Err(error)),
                }
            }
            AudioCommand::StopAllSfx { reply: response } => {
                for sink in sfx_sinks.drain(..) {
                    sink.stop();
                }
                reply(response, Ok(()));
            }
            AudioCommand::SetSfxVolume { volume, reply: response } => {
                sfx_volume = volume;
                sfx_sinks.retain(|sink| !sink.empty());
                for sink in &sfx_sinks {
                    sink.set_volume(volume);
                }
                reply(response, Ok(()));
            }
        }
    }

    if let Some(sink) = bgm_sink {
        sink.stop();
    }
    if let Some(sink) = dialogue_sink {
        sink.stop();
    }
    for sink in sfx_sinks {
        sink.stop();
    }
}
