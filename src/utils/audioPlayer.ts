import { invoke } from "@tauri-apps/api/core";

type FadePlayable = {
  play(path: string): Promise<void>;
  setVolume(volume: number): Promise<void>;
};

type FadeStoppable = {
  stop(): Promise<void>;
  setVolume(volume: number): Promise<void>;
};

async function fadePlayImpl(
  player: FadePlayable,
  path: string,
  time: number,
  volume: { startingVolume: number; targetVolume: number } = {
    startingVolume: 0,
    targetVolume: 1,
  },
): Promise<void> {
  if (
    volume.startingVolume < 0 ||
    volume.startingVolume > 1 ||
    volume.targetVolume < 0 ||
    volume.targetVolume > 1
  ) {
    throw new Error("The volume must be between 0 and 1");
  }

  const diff = volume.targetVolume - volume.startingVolume;

  if (diff === 0) {
    await player.setVolume(volume.targetVolume);
    await player.play(path);
    return;
  }

  await player.setVolume(volume.startingVolume);
  await player.play(path);

  const steps = 20;
  const interval = time / steps;
  const volumeStep = diff / steps;

  for (let i = 1; i <= steps; i++) {
    await new Promise<void>((resolve) => setTimeout(resolve, interval));

    let currentVolume = volume.startingVolume + volumeStep * i;

    if (diff > 0) {
      currentVolume = Math.min(currentVolume, volume.targetVolume);
    } else {
      currentVolume = Math.max(currentVolume, volume.targetVolume);
    }

    await player.setVolume(Number(currentVolume.toFixed(3)));
  }

  await player.setVolume(volume.targetVolume);
}

async function fadeOutStopImpl(
  player: FadeStoppable,
  time: number,
  startingVolume: number = 1,
): Promise<void> {
  if (startingVolume < 0 || startingVolume > 1) {
    throw new Error("The volume must be between 0 and 1");
  }

  const targetVolume = 0;
  const diff = targetVolume - startingVolume;

  if (diff === 0) {
    await player.setVolume(0);
    await player.stop();
    return;
  }

  await player.setVolume(startingVolume);

  const steps = 20;
  const interval = time / steps;
  const volumeStep = diff / steps;

  for (let i = 1; i <= steps; i++) {
    await new Promise<void>((resolve) => setTimeout(resolve, interval));

    let currentVolume = startingVolume + volumeStep * i;
    currentVolume = Math.max(currentVolume, targetVolume);

    await player.setVolume(Number(currentVolume.toFixed(3)));
  }

  await player.setVolume(0);
  await player.stop();
}

export class BgmAudioPlayer {
  private static instance: BgmAudioPlayer;
  private constructor() {}

  public static getInstance(): BgmAudioPlayer {
    return (this.instance ??= new BgmAudioPlayer());
  }

  public async play(path: string): Promise<void> {
    await invoke<void>("playBgm", { path });
  }

  public async stop(): Promise<void> {
    await invoke<void>("stopBgm");
  }

  public async setVolume(volume: number): Promise<void> {
    await invoke<void>("setBgmVolume", { volume: clampVolume(volume) });
  }

  public fadePlay(
    path: string,
    time: number,
    volume?: { startingVolume: number; targetVolume: number },
  ): Promise<void> {
    return fadePlayImpl(this, path, time, volume);
  }

  public fadeOutStop(time: number, startingVolume?: number): Promise<void> {
    return fadeOutStopImpl(this, time, startingVolume);
  }
}

export class DialogueAudioPlayer {
  private static instance: DialogueAudioPlayer;
  private constructor() {}

  public static getInstance(): DialogueAudioPlayer {
    return (this.instance ??= new DialogueAudioPlayer());
  }

  public async play(path: string): Promise<void> {
    await invoke<void>("playDialogue", { path });
  }

  public async stop(): Promise<void> {
    await invoke<void>("stopDialogue");
  }

  public async setVolume(volume: number): Promise<void> {
    await invoke<void>("setDialogueVolume", { volume: clampVolume(volume) });
  }

  public fadePlay(
    path: string,
    time: number,
    volume?: { startingVolume: number; targetVolume: number },
  ): Promise<void> {
    return fadePlayImpl(this, path, time, volume);
  }

  public fadeOutStop(time: number, startingVolume?: number): Promise<void> {
    return fadeOutStopImpl(this, time, startingVolume);
  }
}

export class SFXAudioPlayer {
  private static instance: SFXAudioPlayer;
  private constructor() {}

  public static getInstance(): SFXAudioPlayer {
    return (this.instance ??= new SFXAudioPlayer());
  }

  public async play(path: string): Promise<void> {
    await invoke<void>("playSfx", { path });
  }

  public async stopAll(): Promise<void> {
    await invoke<void>("stopAllSfx");
  }

  public async setVolume(volume: number): Promise<void> {
    await invoke<void>("setSfxVolume", { volume: clampVolume(volume) });
  }

  public fadePlay(
    path: string,
    time: number,
    volume?: { startingVolume: number; targetVolume: number },
  ): Promise<void> {
    return fadePlayImpl(this, path, time, volume);
  }
}

export class AudioPlayer {
  public static readonly bgm = BgmAudioPlayer.getInstance();
  public static readonly dialogue = DialogueAudioPlayer.getInstance();
  public static readonly sfx = SFXAudioPlayer.getInstance();
}

function clampVolume(volume: number): number {
  if (!Number.isFinite(volume)) return 0;
  return Math.min(1, Math.max(0, volume));
}
