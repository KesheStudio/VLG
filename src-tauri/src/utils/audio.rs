use std::{
    collections::{HashMap, HashSet},
    io::Cursor,
    sync::{
        atomic::{AtomicU64, Ordering},
        mpsc::{self, Receiver, RecvTimeoutError, Sender},
        Mutex,
    },
    thread,
    time::{Duration, Instant},
};

use kira::{
    AudioManager, AudioManagerSettings, DefaultBackend, Tween,
    sound::static_sound::{StaticSoundData, StaticSoundHandle},
};

type Reply = Sender<Result<(), String>>;

const FADE_FRAME_MS: u64 = 16;
const FADE_TWEEN_MS: u64 = 32;
const FADE_POLL_MS: u64 = 8;
const IDLE_POLL: Duration = Duration::from_secs(30);

#[derive(Clone, Copy)]
enum Track {
    Bgm,
    Dialogue,
    Sfx(u64),
}

enum Command {
    Load(Track, String, Vec<u8>, Reply),
    Play(Track, String, Vec<u8>, Reply),
    Stop(Track, Reply),
    SetVolume(Track, f32, Reply),
    FadePlay(Track, String, Vec<u8>, u64, f32, f32, Reply),
    FadeOut(Track, u64, f32, Reply),
    PauseAll(Reply),
    ResumeAll(Reply),
    Pause(Track, Reply),
    Resume(Track, Reply),
    #[cfg_attr(not(mobile), allow(dead_code))]
    Lifecycle(bool, Reply),
}

pub struct AudioPlayer {
    tx: Sender<Command>,
    next_sfx_id: AtomicU64,
    loaded_keys: Mutex<HashSet<(u8, String)>>,
}

impl AudioPlayer {
    pub fn new() -> Result<Self, String> {
        let (tx, rx) = mpsc::channel();
        let (ready_tx, ready_rx) = mpsc::sync_channel(1);
        thread::Builder::new()
            .name("vlg-audio-engine".into())
            .spawn(move || {
                let backend = match KiraBackend::new() {
                    Ok(backend) => backend,
                    Err(error) => {
                        let _ = ready_tx.send(Err(error));
                        return;
                    }
                };
                if ready_tx.send(Ok(())).is_ok() {
                    run_worker(rx, backend);
                }
            })
            .map_err(|e| format!("cannot start audio worker: {e}"))?;
        ready_rx
            .recv()
            .map_err(|_| "audio worker exited during initialization".to_string())??;
        Ok(Self { tx, next_sfx_id: AtomicU64::new(1), loaded_keys: Mutex::new(HashSet::new()) })
    }

    fn send(&self, build: impl FnOnce(Reply) -> Command) -> Result<(), String> {
        let (reply_tx, reply_rx) = mpsc::channel();
        self.tx.send(build(reply_tx)).map_err(|_| "audio worker is unavailable".to_string())?;
        reply_rx.recv().map_err(|_| "audio worker did not return a result".to_string())?
    }

    pub fn load_bgm(&self, key: String, bytes: Vec<u8>) -> Result<(), String> {
        self.send(|r| Command::Load(Track::Bgm, key.clone(), bytes, r))?;
        self.mark_loaded(0, key)
    }
    pub fn load_dialogue(&self, key: String, bytes: Vec<u8>) -> Result<(), String> {
        self.send(|r| Command::Load(Track::Dialogue, key.clone(), bytes, r))?;
        self.mark_loaded(1, key)
    }
    pub fn load_sfx(&self, key: String, bytes: Vec<u8>) -> Result<(), String> {
        self.send(|r| Command::Load(Track::Sfx(0), key.clone(), bytes, r))?;
        self.mark_loaded(2, key)
    }
    fn mark_loaded(&self, category: u8, key: String) -> Result<(), String> {
        self.loaded_keys.lock().map_err(|_| "audio cache lock poisoned".to_string())?.insert((category, key));
        Ok(())
    }
    pub fn is_bgm_loaded(&self, key: &str) -> bool { self.loaded_keys.lock().map(|s| s.contains(&(0, key.to_owned()))).unwrap_or(false) }
    pub fn is_dialogue_loaded(&self, key: &str) -> bool { self.loaded_keys.lock().map(|s| s.contains(&(1, key.to_owned()))).unwrap_or(false) }
    pub fn is_sfx_loaded(&self, key: &str) -> bool { self.loaded_keys.lock().map(|s| s.contains(&(2, key.to_owned()))).unwrap_or(false) }
    pub fn play_bgm(&self, key: String, bytes: Vec<u8>) -> Result<(), String> {
        self.send(|r| Command::Play(Track::Bgm, key.clone(), bytes, r))?;
        self.mark_loaded(0, key)
    }
    pub fn stop_bgm(&self) -> Result<(), String> { self.send(|r| Command::Stop(Track::Bgm, r)) }
    pub fn set_bgm_volume(&self, v: f32) -> Result<(), String> { self.send(|r| Command::SetVolume(Track::Bgm, v, r)) }
    pub fn play_dialogue(&self, key: String, bytes: Vec<u8>) -> Result<(), String> {
        self.send(|r| Command::Play(Track::Dialogue, key.clone(), bytes, r))?;
        self.mark_loaded(1, key)
    }
    pub fn stop_dialogue(&self) -> Result<(), String> { self.send(|r| Command::Stop(Track::Dialogue, r)) }
    pub fn set_dialogue_volume(&self, v: f32) -> Result<(), String> { self.send(|r| Command::SetVolume(Track::Dialogue, v, r)) }
    pub fn play_sfx(&self, key: String, bytes: Vec<u8>) -> Result<(), String> {
        let id = self.next_sfx_id.fetch_add(1, Ordering::Relaxed);
        self.send(|r| Command::Play(Track::Sfx(id), key.clone(), bytes, r))?;
        self.mark_loaded(2, key)
    }
    pub fn stop_all_sfx(&self) -> Result<(), String> { self.send(|r| Command::Stop(Track::Sfx(0), r)) }
    pub fn set_sfx_volume(&self, v: f32) -> Result<(), String> { self.send(|r| Command::SetVolume(Track::Sfx(0), v, r)) }

    pub fn fade_play_bgm(&self, key: String, b: Vec<u8>, ms: u64, from: f32, to: f32) -> Result<(), String> { self.fade_play(Track::Bgm, key, b, ms, from, to) }
    pub fn fade_play_dialogue(&self, key: String, b: Vec<u8>, ms: u64, from: f32, to: f32) -> Result<(), String> { self.fade_play(Track::Dialogue, key, b, ms, from, to) }
    pub fn fade_play_sfx(&self, key: String, b: Vec<u8>, ms: u64, from: f32, to: f32) -> Result<(), String> {
        let id = self.next_sfx_id.fetch_add(1, Ordering::Relaxed);
        self.fade_play(Track::Sfx(id), key, b, ms, from, to)
    }
    fn fade_play(&self, track: Track, key: String, bytes: Vec<u8>, ms: u64, from: f32, to: f32) -> Result<(), String> {
        validate_fade(ms, from, to)?;
        let category = match track { Track::Bgm => Some(0), Track::Dialogue => Some(1), Track::Sfx(_) => Some(2) };
        self.send(|r| Command::FadePlay(track, key.clone(), bytes, ms, from, to, r))?;
        if let Some(category) = category { self.mark_loaded(category, key)?; }
        Ok(())
    }
    pub fn fade_out_stop_bgm(&self, ms: u64, from: f32) -> Result<(), String> { self.fade_out(Track::Bgm, ms, from) }
    pub fn fade_out_stop_dialogue(&self, ms: u64, from: f32) -> Result<(), String> { self.fade_out(Track::Dialogue, ms, from) }
    fn fade_out(&self, track: Track, ms: u64, from: f32) -> Result<(), String> {
        validate_fade(ms, from, 0.0)?;
        self.send(|r| Command::FadeOut(track, ms, from, r))
    }
    pub fn pause_all(&self) -> Result<(), String> { self.send(Command::PauseAll) }
    pub fn resume_all(&self) -> Result<(), String> { self.send(Command::ResumeAll) }
    pub fn pause_bgm(&self) -> Result<(), String> { self.send(|r| Command::Pause(Track::Bgm, r)) }
    pub fn resume_bgm(&self) -> Result<(), String> { self.send(|r| Command::Resume(Track::Bgm, r)) }
    pub fn pause_dialogue(&self) -> Result<(), String> { self.send(|r| Command::Pause(Track::Dialogue, r)) }
    pub fn resume_dialogue(&self) -> Result<(), String> { self.send(|r| Command::Resume(Track::Dialogue, r)) }
    pub fn pause_all_sfx(&self) -> Result<(), String> { self.send(|r| Command::Pause(Track::Sfx(0), r)) }
    pub fn resume_all_sfx(&self) -> Result<(), String> { self.send(|r| Command::Resume(Track::Sfx(0), r)) }
    #[cfg_attr(not(mobile), allow(dead_code))]
    pub fn set_lifecycle_paused(&self, paused: bool) -> Result<(), String> { self.send(|r| Command::Lifecycle(paused, r)) }
}

fn validate_fade(ms: u64, from: f32, to: f32) -> Result<(), String> {
    if ms > 600_000 { return Err("fade duration must not exceed 600000 ms".into()); }
    if !from.is_finite() || !to.is_finite() || !(0.0..=1.0).contains(&from) || !(0.0..=1.0).contains(&to) {
        return Err("fade volume must be between 0 and 1".into());
    }
    Ok(())
}

fn linear_to_db(volume: f32) -> f32 {
    if volume <= 0.000_001 { -60.0 } else { 20.0 * volume.log10() }
}
fn tween(ms: u64) -> Tween { Tween { duration: Duration::from_millis(ms), ..Tween::default() } }

fn fade_shape(progress: f64) -> f64 {
    let t = progress.clamp(0.0, 1.0);
    t * t * (3.0 - 2.0 * t)
}

fn fade_gain(from: f32, to: f32, progress: f64) -> f32 {
    let from = from.clamp(0.0, 1.0) as f64;
    let to = to.clamp(0.0, 1.0) as f64;
    (from + (to - from) * fade_shape(progress)) as f32
}

#[derive(Clone, Copy)]
struct Fade {
    from: f32,
    to: f32,
    started: Instant,
    duration: Duration,
    stop_when_done: bool,
}

impl Fade {
    fn progress(&self, now: Instant) -> f64 {
        let elapsed = now.saturating_duration_since(self.started).as_secs_f64();
        elapsed / self.duration.as_secs_f64().max(f64::EPSILON)
    }
}

struct Voice {
    handle: StaticSoundHandle,
    gain: f32,
    fade: Option<Fade>,
}

impl Voice {
    fn set_gain(&mut self, gain: f32, tween: Tween) {
        let gain = gain.clamp(0.0, 1.0);
        self.gain = gain;
        self.handle.set_volume(linear_to_db(gain), tween);
    }
}

fn advance_fade(voice: &mut Voice, now: Instant) -> bool {
    let Some(fade) = voice.fade else { return false };
    let progress = fade.progress(now);
    let finished = progress >= 1.0;
    let gain = if finished { fade.to } else { fade_gain(fade.from, fade.to, progress) };
    voice.set_gain(gain, tween(FADE_TWEEN_MS));
    if !finished { return false }
    voice.fade = None;
    if fade.stop_when_done {
        voice.handle.stop(Tween::default());
        return true;
    }
    false
}

trait AudioOutputBackend {
    fn load(&mut self, track: Track, key: String, bytes: Vec<u8>) -> Result<(), String>;
    fn play(&mut self, track: Track, key: String, bytes: Vec<u8>, fade: Option<(u64, f32, f32)>) -> Result<(), String>;
    fn stop(&mut self, track: Track);
    fn set_volume(&mut self, track: Track, volume: f32);
    fn fade_out(&mut self, track: Track, ms: u64, from: f32);
    fn set_pause_all(&mut self, paused: bool);
    fn set_pause(&mut self, track: Track, paused: bool);
    fn set_lifecycle_paused(&mut self, paused: bool);
    fn needs_tick(&self) -> bool;
    fn tick(&mut self);
}

struct KiraBackend {
    manager: AudioManager<DefaultBackend>,
    bgm: Option<Voice>,
    dialogue: Option<Voice>,
    sfx: Vec<(u64, Voice)>,
    retiring: Vec<Voice>,
    bgm_cache: HashMap<String, StaticSoundData>,
    dialogue_cache: HashMap<String, StaticSoundData>,
    sfx_cache: HashMap<String, StaticSoundData>,
    bgm_volume: f32,
    dialogue_volume: f32,
    sfx_volume: f32,
    paused_all: bool,
    paused_bgm: bool,
    paused_dialogue: bool,
    paused_sfx: bool,
    lifecycle_paused: bool,
    last_fade_tick: Instant,
}

impl KiraBackend {
    fn new() -> Result<Self, String> {
        let manager = AudioManager::<DefaultBackend>::new(AudioManagerSettings::default())
            .map_err(|e| format!("audio device initialization failed: {e}"))?;
        Ok(Self {
            manager, bgm: None, dialogue: None, sfx: Vec::new(), retiring: Vec::new(),
            bgm_cache: HashMap::new(), dialogue_cache: HashMap::new(), sfx_cache: HashMap::new(),
            bgm_volume: 1.0, dialogue_volume: 1.0, sfx_volume: 1.0,
            paused_all: false, paused_bgm: false, paused_dialogue: false,
            paused_sfx: false, lifecycle_paused: false,
            last_fade_tick: Instant::now(),
        })
    }

    fn load(&mut self, track: Track, key: String, bytes: Vec<u8>) -> Result<(), String> {
        if key.is_empty() { return Err("audio cache key is empty".into()); }
        if bytes.is_empty() { return Err("audio resource is empty".into()); }
        let data = StaticSoundData::from_cursor(Cursor::new(bytes))
            .map_err(|e| format!("audio decode failed: {e}"))?;
        match track {
            Track::Bgm => { self.bgm_cache.insert(key, data); }
            Track::Dialogue => { self.dialogue_cache.insert(key, data); }
            Track::Sfx(_) => { self.sfx_cache.insert(key, data); }
        }
        Ok(())
    }

    fn play(&mut self, track: Track, key: String, bytes: Vec<u8>, fade: Option<(u64, f32, f32)>) -> Result<(), String> {
        let (base_volume, looping) = match track {
            Track::Bgm => (self.bgm_volume, true),
            Track::Dialogue => (self.dialogue_volume, false),
            Track::Sfx(_) => (self.sfx_volume, false),
        };
        let cached = if key.is_empty() { None } else { match track {
            Track::Bgm => self.bgm_cache.get(&key),
            Track::Dialogue => self.dialogue_cache.get(&key),
            Track::Sfx(_) => self.sfx_cache.get(&key),
        }.cloned() };
        let data = match cached {
            Some(data) => data,
            None => {
                if bytes.is_empty() { return Err(format!("audio resource is not loaded: {key}")); }
                let data = StaticSoundData::from_cursor(Cursor::new(bytes))
                    .map_err(|e| format!("audio decode failed: {e}"))?;
                if !key.is_empty() { match track {
                    Track::Bgm => { self.bgm_cache.insert(key.clone(), data.clone()); }
                    Track::Dialogue => { self.dialogue_cache.insert(key.clone(), data.clone()); }
                    Track::Sfx(_) => { self.sfx_cache.insert(key.clone(), data.clone()); }
                }}
                data
            }
        };

        let start_gain = fade.map_or(base_volume, |(_, from, _)| clamp_volume(from));
        let mut data = data;
        data.settings.volume = linear_to_db(start_gain).into();
        data.settings.fade_in_tween = None;

        let mut handle = self.manager.play(data)
            .map_err(|e| format!("audio playback start failed: {e}"))?;
        if looping { handle.set_loop_region(0.0..); }

        let now = Instant::now();
        let mut voice = Voice { handle, gain: start_gain, fade: None };
        if let Some((ms, from, to)) = fade {
            let (from, to) = (clamp_volume(from), clamp_volume(to));
            if ms == 0 {
                voice.set_gain(to, Tween::default());
            } else {
                voice.fade = Some(Fade {
                    from, to, started: now,
                    duration: Duration::from_millis(ms),
                    stop_when_done: false,
                });
            }
        }

        let replaced = match track {
            Track::Bgm => self.bgm.replace(voice),
            Track::Dialogue => self.dialogue.replace(voice),
            Track::Sfx(id) => { self.sfx.push((id, voice)); None }
        };
        if let Some(mut old) = replaced {
            match fade {
                Some((ms, _, _)) if ms > 0 => {
                    old.fade = Some(Fade {
                        from: old.gain, to: 0.0, started: now,
                        duration: Duration::from_millis(ms),
                        stop_when_done: true,
                    });
                    self.retiring.push(old);
                }
                _ => old.handle.stop(Tween::default()),
            }
        }
        self.apply_pause_state(track);
        Ok(())
    }

    fn apply_pause_state(&mut self, track: Track) {
        match track {
            Track::Bgm => if let Some(v) = &mut self.bgm {
                if self.lifecycle_paused || self.paused_all || self.paused_bgm { v.handle.pause(Tween::default()); }
            },
            Track::Dialogue => if let Some(v) = &mut self.dialogue {
                if self.lifecycle_paused || self.paused_all || self.paused_dialogue { v.handle.pause(Tween::default()); }
            },
            Track::Sfx(_) => {
                if self.lifecycle_paused || self.paused_all || self.paused_sfx {
                    for (_, v) in &mut self.sfx { v.handle.pause(Tween::default()); }
                }
            }
        }
    }

    fn set_volume(&mut self, track: Track, volume: f32) {
        let volume = clamp_volume(volume);
        match track {
            Track::Bgm => {
                self.bgm_volume = volume;
                if let Some(v) = &mut self.bgm { v.fade = None; v.set_gain(volume, Tween::default()); }
            }
            Track::Dialogue => {
                self.dialogue_volume = volume;
                if let Some(v) = &mut self.dialogue { v.fade = None; v.set_gain(volume, Tween::default()); }
            }
            Track::Sfx(_) => {
                self.sfx_volume = volume;
                for (_, v) in &mut self.sfx { v.fade = None; v.set_gain(volume, Tween::default()); }
            }
        }
    }

    fn stop(&mut self, track: Track) {
        match track {
            Track::Bgm => if let Some(mut v) = self.bgm.take() { v.handle.stop(Tween::default()); },
            Track::Dialogue => if let Some(mut v) = self.dialogue.take() { v.handle.stop(Tween::default()); },
            Track::Sfx(_) => { for (_, mut v) in self.sfx.drain(..) { v.handle.stop(Tween::default()); } }
        }
    }

    fn fade_out(&mut self, track: Track, ms: u64, _from: f32) {
        if ms == 0 { return self.stop(track); }
        let now = Instant::now();
        let duration = Duration::from_millis(ms);
        let fade_from_current = |voice: &mut Voice| {
            voice.fade = Some(Fade {
                from: voice.gain, to: 0.0, started: now, duration, stop_when_done: true,
            });
        };
        match track {
            Track::Bgm => if let Some(v) = &mut self.bgm { fade_from_current(v); },
            Track::Dialogue => if let Some(v) = &mut self.dialogue { fade_from_current(v); },
            Track::Sfx(_) => for (_, v) in &mut self.sfx { fade_from_current(v); }
        }
    }

    fn set_pause_flags(&mut self) {
        let all = self.paused_all || self.lifecycle_paused;
        if let Some(v) = &mut self.bgm {
            if all || self.paused_bgm { v.handle.pause(Tween::default()); }
            else { v.handle.resume(Tween::default()); }
        }
        if let Some(v) = &mut self.dialogue {
            if all || self.paused_dialogue { v.handle.pause(Tween::default()); }
            else { v.handle.resume(Tween::default()); }
        }
        for (_, v) in &mut self.sfx {
            if all || self.paused_sfx { v.handle.pause(Tween::default()); }
            else { v.handle.resume(Tween::default()); }
        }
    }

    fn has_active_fade(&self) -> bool {
        self.bgm.as_ref().is_some_and(|v| v.fade.is_some())
            || self.dialogue.as_ref().is_some_and(|v| v.fade.is_some())
            || self.sfx.iter().any(|(_, v)| v.fade.is_some())
            || self.retiring.iter().any(|v| v.fade.is_some())
    }

    fn tick(&mut self) {
        let now = Instant::now();
        if now.saturating_duration_since(self.last_fade_tick)
            < Duration::from_millis(FADE_FRAME_MS.saturating_sub(4))
        {
            return;
        }
        self.last_fade_tick = now;

        if self.bgm.as_mut().is_some_and(|v| advance_fade(v, now)) { self.bgm = None; }
        if self.dialogue.as_mut().is_some_and(|v| advance_fade(v, now)) { self.dialogue = None; }
        self.sfx.retain_mut(|(_, v)| !advance_fade(v, now));
        let mut retiring = std::mem::take(&mut self.retiring);
        retiring.retain_mut(|v| !advance_fade(v, now));
        self.retiring = retiring;
    }
}

impl AudioOutputBackend for KiraBackend {
    fn load(&mut self, track: Track, key: String, bytes: Vec<u8>) -> Result<(), String> { KiraBackend::load(self, track, key, bytes) }
    fn play(&mut self, track: Track, key: String, bytes: Vec<u8>, fade: Option<(u64, f32, f32)>) -> Result<(), String> { KiraBackend::play(self, track, key, bytes, fade) }
    fn stop(&mut self, track: Track) { KiraBackend::stop(self, track); }
    fn set_volume(&mut self, track: Track, volume: f32) { KiraBackend::set_volume(self, track, volume); }
    fn fade_out(&mut self, track: Track, ms: u64, from: f32) { KiraBackend::fade_out(self, track, ms, from); }
    fn set_pause_all(&mut self, paused: bool) { self.paused_all = paused; self.set_pause_flags(); }
    fn set_pause(&mut self, track: Track, paused: bool) {
        match track { Track::Bgm => self.paused_bgm = paused, Track::Dialogue => self.paused_dialogue = paused, Track::Sfx(_) => self.paused_sfx = paused }
        self.set_pause_flags();
    }
    fn set_lifecycle_paused(&mut self, paused: bool) { self.lifecycle_paused = paused; self.set_pause_flags(); }
    fn needs_tick(&self) -> bool { self.has_active_fade() }
    fn tick(&mut self) { KiraBackend::tick(self); }
}

fn clamp_volume(v: f32) -> f32 { if v.is_finite() { v.clamp(0.0, 1.0) } else { 0.0 } }

fn run_worker<B: AudioOutputBackend>(rx: Receiver<Command>, mut backend: B) {
    loop {
        if backend.needs_tick() { backend.tick(); }
        let timeout = if backend.needs_tick() { Duration::from_millis(FADE_POLL_MS) } else { IDLE_POLL };
        match rx.recv_timeout(timeout) {
            Ok(command) => handle_command(&mut backend, command),
            Err(RecvTimeoutError::Timeout) => {}
            Err(RecvTimeoutError::Disconnected) => break,
        }
    }
}

fn handle_command<B: AudioOutputBackend>(backend: &mut B, command: Command) {
    let (reply, result) = match command {
        Command::Load(track, key, bytes, reply) => (reply, backend.load(track, key, bytes)),
        Command::Play(track, key, bytes, reply) => (reply, backend.play(track, key, bytes, None)),
        Command::Stop(track, reply) => { backend.stop(track); (reply, Ok(())) },
        Command::SetVolume(track, volume, reply) => { backend.set_volume(track, volume); (reply, Ok(())) },
        Command::FadePlay(track, key, bytes, ms, from, to, reply) => (reply, backend.play(track, key, bytes, Some((ms, from, to)))),
        Command::FadeOut(track, ms, from, reply) => { backend.fade_out(track, ms, from); (reply, Ok(())) },
        Command::PauseAll(reply) => { backend.set_pause_all(true); (reply, Ok(())) },
        Command::ResumeAll(reply) => { backend.set_pause_all(false); (reply, Ok(())) },
        Command::Pause(track, reply) => { backend.set_pause(track, true); (reply, Ok(())) },
        Command::Resume(track, reply) => { backend.set_pause(track, false); (reply, Ok(())) },
        Command::Lifecycle(paused, reply) => { backend.set_lifecycle_paused(paused); (reply, Ok(())) }
    };
    let _ = reply.send(result);
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn endpoints_are_exact() {
        assert_eq!(fade_gain(0.0, 1.0, 0.0), 0.0);
        assert_eq!(fade_gain(0.0, 1.0, 1.0), 1.0);
        assert_eq!(fade_gain(1.0, 0.0, 0.0), 1.0);
        assert_eq!(fade_gain(1.0, 0.0, 1.0), 0.0);
        assert!((fade_gain(0.3, 0.8, 0.0) - 0.3).abs() < 1e-6);
        assert!((fade_gain(0.3, 0.8, 1.0) - 0.8).abs() < 1e-6);
    }

    #[test]
    fn curve_is_monotonic_and_eased() {
        let mut previous = fade_gain(0.0, 1.0, 0.0);
        for step in 1..=1000 {
            let gain = fade_gain(0.0, 1.0, step as f64 / 1000.0);
            assert!(gain >= previous, "fade-in must never go backwards");
            previous = gain;
        }
        assert!(fade_gain(0.0, 1.0, 0.01) < 0.001);
        assert!(1.0 - fade_gain(0.0, 1.0, 0.99) < 0.001);
    }

    #[test]
    fn crossfade_pair_keeps_a_constant_sum() {
        for step in 0..=100 {
            let p = step as f64 / 100.0;
            let out = fade_gain(1.0, 0.0, p);
            let new = fade_gain(0.0, 1.0, p);
            assert!((out + new - 1.0).abs() < 1e-6);
        }
    }

    #[test]
    fn fade_curve_table() {
        let duration_ms: u64 = 1000;
        let (from, to) = (0.0_f32, 1.0_f32);
        let frames = duration_ms / FADE_FRAME_MS;
        let mut csv = String::from("time_ms,progress,new_amplitude,new_db,old_kira_amplitude,old_kira_db\n");
        for frame in 0..=frames {
            let t_ms = frame * FADE_FRAME_MS;
            let progress = (t_ms as f64 / duration_ms as f64).min(1.0);
            let amplification = fade_gain(from, to, progress);
            let old_db = -60.0 + 60.0 * progress;
            let old_amplitude = 10f64.powf(old_db / 20.0);
            csv.push_str(&format!(
                "{t_ms},{progress:.3},{amplification:.5},{:.2},{old_amplitude:.5},{old_db:.1}\n",
                linear_to_db(amplification)
            ));
        }
        println!("{csv}");
        let path = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR"))
            .join("target")
            .join("fade_curve.csv");
        let _ = std::fs::create_dir_all(path.parent().unwrap());
        std::fs::write(&path, &csv).ok();
        println!("wrote {}", path.display());
    }
}
