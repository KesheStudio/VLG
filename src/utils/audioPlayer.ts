import { invoke } from "@tauri-apps/api/core";

type FadeVolume = { startingVolume: number; targetVolume: number };
type QueueResource = { key: string; path: string };
type QueueBatch = Record<string, string> | QueueResource[] | string[];
type QueueWaiter = { resolve: () => void; reject: (error: unknown) => void };

const defaultFade: FadeVolume = { startingVolume: 0, targetVolume: 1 };

function checkFade(time: number, volume: FadeVolume): void {
  if (!Number.isFinite(time) || time < 0 || time > 600_000)
    throw new Error("Fade time must be between 0 and 600000 ms");
  if (
    ![volume.startingVolume, volume.targetVolume].every(
      (v) => Number.isFinite(v) && v >= 0 && v <= 1,
    )
  )
    throw new Error("The volume must be between 0 and 1");
}

export class AudioLoadQueue {
  private readonly resources = new Map<string, string>();
  private readonly pending: string[] = [];
  private readonly pendingSet = new Set<string>();
  private readonly inFlight = new Set<string>();
  private readonly loaded = new Set<string>();
  private readonly waiters = new Map<string, QueueWaiter[]>();
  private worker?: Promise<void>;

  public constructor(private readonly loadResource: (path: string) => Promise<void>) {}

  public add(keyOrPath: string, path?: string): void {
    const key = keyOrPath;
    const resourcePath = path ?? keyOrPath;
    this.assertString(key, "key");
    this.assertString(resourcePath, "path");
    this.resources.set(key, resourcePath);
    this.schedule(resourcePath);
  }

  public addMany(entries: QueueBatch): void {
    if (Array.isArray(entries)) {
      for (const entry of entries) {
        if (typeof entry === "string") this.add(entry);
        else this.add(entry.key, entry.path);
      }
      return;
    }
    for (const [key, path] of Object.entries(entries)) this.add(key, path);
  }

  public get(key: string): string | undefined {
    return this.resources.get(key);
  }

  public has(key: string): boolean {
    return this.resources.has(key);
  }

  public remove(key: string): boolean {
    return this.resources.delete(key);
  }

  public clear(): void {
    this.resources.clear();
    const cancelled = this.pending.splice(0);
    this.pendingSet.clear();
    for (const path of cancelled)
      this.settle(path, new Error("Audio preload was cancelled by queue.clear()"));
  }

  public async loadAll(): Promise<void> {
    const keys = [...this.resources.keys()];
    await Promise.all(keys.map((key) => this.ensureLoaded(key)));
  }

  public async ensureLoaded(keyOrPath: string): Promise<string> {
    const path = this.resources.get(keyOrPath) ?? keyOrPath;
    this.assertString(path, "path");
    if (this.loaded.has(path)) return path;

    const wait = new Promise<void>((resolve, reject) => {
      const list = this.waiters.get(path) ?? [];
      list.push({ resolve, reject });
      this.waiters.set(path, list);
    });
    this.schedule(path);
    await wait;
    return path;
  }

  public isLoaded(keyOrPath: string): boolean {
    const path = this.resources.get(keyOrPath) ?? keyOrPath;
    return this.loaded.has(path);
  }

  private assertString(value: string, name: string): void {
    if (typeof value !== "string" || value.trim().length === 0)
      throw new Error(`Audio queue ${name} must be a non-empty string`);
  }

  private schedule(path: string): void {
    if (this.loaded.has(path) || this.pendingSet.has(path) || this.inFlight.has(path)) return;
    this.pending.push(path);
    this.pendingSet.add(path);
    this.startWorker();
  }

  private startWorker(): void {
    if (this.worker) return;
    this.worker = this.runWorker().finally(() => {
      this.worker = undefined;
      if (this.pending.length > 0) this.startWorker();
    });
  }

  private async runWorker(): Promise<void> {
    while (this.pending.length > 0) {
      const path = this.pending.shift()!;
      this.pendingSet.delete(path);
      this.inFlight.add(path);
      try {
        await this.loadResource(path);
        this.loaded.add(path);
            this.settle(path);
      } catch (error) {
        this.settle(path, error, true);
      } finally {
        this.inFlight.delete(path);
      }
    }
  }

  private settle(path: string, error?: unknown, failed = false): void {
    const list = this.waiters.get(path) ?? [];
    this.waiters.delete(path);
    for (const waiter of list) {
      if (failed) waiter.reject(error);
      else waiter.resolve();
    }
  }
}

function createQueue(command: string): AudioLoadQueue {
  return new AudioLoadQueue(async (path) => {
    await invoke<void>(command, { path });
  });
}

export class BgmAudioPlayer {
  private static instance: BgmAudioPlayer;
  public readonly queue = createQueue("loadBgm");
  private constructor() {}
  public static getInstance(): BgmAudioPlayer {
    return (this.instance ??= new BgmAudioPlayer());
  }

  public async load(keyOrPath: string, path?: string): Promise<void> {
    this.queue.add(keyOrPath, path);
    await this.queue.ensureLoaded(keyOrPath);
  }
  public async play(keyOrPath: string): Promise<void> {
    const path = this.queue.has(keyOrPath)
      ? await this.queue.ensureLoaded(keyOrPath)
      : keyOrPath;
    await invoke<void>("playBgm", { path });
  }
  public async stop(): Promise<void> { await invoke<void>("stopBgm"); }
  public async setVolume(volume: number): Promise<void> {
    await invoke<void>("setBgmVolume", { volume: clampVolume(volume) });
  }
  public async fadePlay(
    keyOrPath: string,
    time: number,
    volume: FadeVolume = defaultFade,
  ): Promise<void> {
    checkFade(time, volume);
    const path = this.queue.has(keyOrPath)
      ? await this.queue.ensureLoaded(keyOrPath)
      : keyOrPath;
    await invoke<void>("fadePlayBgm", {
      path,
      time: Math.round(time),
      startingVolume: volume.startingVolume,
      targetVolume: volume.targetVolume,
    });
  }
  public async fadeOutStop(time: number, startingVolume = 1): Promise<void> {
    checkFade(time, { startingVolume, targetVolume: 0 });
    await invoke<void>("fadeOutStopBgm", { time: Math.round(time), startingVolume });
  }
}

export class DialogueAudioPlayer {
  private static instance: DialogueAudioPlayer;
  public readonly queue = createQueue("loadDialogue");
  private constructor() {}
  public static getInstance(): DialogueAudioPlayer {
    return (this.instance ??= new DialogueAudioPlayer());
  }
  public async load(keyOrPath: string, path?: string): Promise<void> {
    this.queue.add(keyOrPath, path);
    await this.queue.ensureLoaded(keyOrPath);
  }
  public async play(keyOrPath: string): Promise<void> {
    const path = this.queue.has(keyOrPath)
      ? await this.queue.ensureLoaded(keyOrPath)
      : keyOrPath;
    await invoke<void>("playDialogue", { path });
  }
  public async stop(): Promise<void> { await invoke<void>("stopDialogue"); }
  public async setVolume(volume: number): Promise<void> {
    await invoke<void>("setDialogueVolume", { volume: clampVolume(volume) });
  }
  public async fadePlay(
    keyOrPath: string,
    time: number,
    volume: FadeVolume = defaultFade,
  ): Promise<void> {
    checkFade(time, volume);
    const path = this.queue.has(keyOrPath)
      ? await this.queue.ensureLoaded(keyOrPath)
      : keyOrPath;
    await invoke<void>("fadePlayDialogue", {
      path,
      time: Math.round(time),
      startingVolume: volume.startingVolume,
      targetVolume: volume.targetVolume,
    });
  }
  public async fadeOutStop(time: number, startingVolume = 1): Promise<void> {
    checkFade(time, { startingVolume, targetVolume: 0 });
    await invoke<void>("fadeOutStopDialogue", { time: Math.round(time), startingVolume });
  }
}

export class SFXAudioPlayer {
  private static instance: SFXAudioPlayer;
  public readonly queue = createQueue("loadSfx");
  private constructor() {}
  public static getInstance(): SFXAudioPlayer {
    return (this.instance ??= new SFXAudioPlayer());
  }
  public async load(keyOrPath: string, path?: string): Promise<void> {
    this.queue.add(keyOrPath, path);
    await this.queue.ensureLoaded(keyOrPath);
  }
  public async play(keyOrPath: string): Promise<void> {
    const path = this.queue.has(keyOrPath)
      ? await this.queue.ensureLoaded(keyOrPath)
      : keyOrPath;
    await invoke<void>("playSfx", { path });
  }
  public async stopAll(): Promise<void> { await invoke<void>("stopAllSfx"); }
  public async setVolume(volume: number): Promise<void> {
    await invoke<void>("setSfxVolume", { volume: clampVolume(volume) });
  }
  public async fadePlay(
    keyOrPath: string,
    time: number,
    volume: FadeVolume = defaultFade,
  ): Promise<void> {
    checkFade(time, volume);
    const path = this.queue.has(keyOrPath)
      ? await this.queue.ensureLoaded(keyOrPath)
      : keyOrPath;
    await invoke<void>("fadePlaySfx", {
      path,
      time: Math.round(time),
      startingVolume: volume.startingVolume,
      targetVolume: volume.targetVolume,
    });
  }
}

export class AudioPlayer {
  public static readonly bgm = BgmAudioPlayer.getInstance();
  public static readonly dialogue = DialogueAudioPlayer.getInstance();
  public static readonly sfx = SFXAudioPlayer.getInstance();

  public static async pauseAll(): Promise<void> { await invoke<void>("pauseAll"); }
  public static async resumeAll(): Promise<void> { await invoke<void>("resumeAll"); }
  public static async pauseBgm(): Promise<void> { await invoke<void>("pauseBgm"); }
  public static async resumeBgm(): Promise<void> { await invoke<void>("resumeBgm"); }
  public static async pauseDialogue(): Promise<void> { await invoke<void>("pauseDialogue"); }
  public static async resumeDialogue(): Promise<void> { await invoke<void>("resumeDialogue"); }
  public static async pauseAllSfx(): Promise<void> { await invoke<void>("pauseAllSfx"); }
  public static async resumeAllSfx(): Promise<void> { await invoke<void>("resumeAllSfx"); }
}

function clampVolume(volume: number): number {
  if (!Number.isFinite(volume)) return 0;
  return Math.min(1, Math.max(0, volume));
}
