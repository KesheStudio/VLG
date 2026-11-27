import { invoke } from "@tauri-apps/api/core";
import { BlobUrl } from "@/utils/blobUrl";
import { type MimeType, mimeFromPath } from "@/types/mime";

export interface ReadOptions {
  path: string;
  requiresDecrypt?: boolean;
}

export class FileAPI {
  static async read(path: string, requiresDecrypt = true): Promise<number[]> {
    return invoke<number[]>("read", { path, requiresDecrypt });
  }

  static async readAsBlobUrl(
    path: string,
    mime?: MimeType,
    requiresDecrypt = true,
  ): Promise<BlobUrl> {
    const bytes = await invoke<number[]>("read", { path, requiresDecrypt });
    const resolvedMime = mime ?? mimeFromPath(path);
    return new BlobUrl(bytes, resolvedMime);
  }

  static async readRjs(path: string): Promise<string> {
    return invoke<string>("read_rjs", { path });
  }

  static async readRjsAs<T>(path: string): Promise<T> {
    const jsonStr = await invoke<string>("read_rjs", { path });
    return JSON.parse(jsonStr) as T;
  }

  static async readConfig<T>(path: string): Promise<T> {
    try {
      const bytes = await invoke<number[]>("read", {
        path,
        requiresDecrypt: false,
      });
      const jsonStr = new TextDecoder("utf-8", { fatal: true }).decode(
        new Uint8Array(bytes),
      );
      return JSON.parse(jsonStr) as T;
    } catch (e) {
      throw new Error(`[readConfig] 解析配置文件 "${path}" 失败: ${e}`);
    }
  }
}
