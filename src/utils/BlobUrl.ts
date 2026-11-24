import { type MimeType } from "@/types/mime";

export class BlobUrl implements Disposable {
  private _url: string | null = null;
  private _revoked = false;

  constructor(
    source: Uint8Array | ArrayBuffer | Blob | File | number[],
    mime?: MimeType,
  ) {
    let blob: Blob;

    if (Array.isArray(source)) {
      blob = new Blob([new Uint8Array(source) as any], {
        type: mime ?? "application/octet-stream",
      });
    } else if (source instanceof Blob) {
      blob = source;
    } else if (source instanceof Uint8Array) {
      blob = new Blob([source as any], {
        type: mime ?? "application/octet-stream",
      });
    } else if (source instanceof ArrayBuffer) {
      blob = new Blob([source as any], {
        type: mime ?? "application/octet-stream",
      });
    } else {
      blob = new Blob([source as any]);
    }

    this._url = URL.createObjectURL(blob);
  }

  get url(): string {
    if (this._revoked || !this._url) {
      throw new Error("[BlobUrl] URL has been revoked");
    }
    return this._url;
  }

  revoke(): void {
    if (this._revoked || !this._url) return;
    URL.revokeObjectURL(this._url);
    this._revoked = true;
  }

  [Symbol.dispose](): void {
    this.revoke();
  }
}
