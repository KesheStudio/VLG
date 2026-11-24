export type MimeType =
  | 'image/png'
  | 'image/jpeg'
  | 'image/gif'
  | 'image/webp'
  | 'image/svg+xml'
  | 'image/bmp'
  | 'audio/mpeg'
  | 'audio/wav'
  | 'audio/ogg'
  | 'audio/aac'
  | 'audio/flac'
  | 'video/mp4'
  | 'video/webm'
  | 'application/json'
  | 'application/octet-stream'
  | 'text/plain'
  | 'text/html'
  | 'text/css'
  | 'application/javascript'

export const Mime = {
  PNG: 'image/png',
  JPEG: 'image/jpeg',
  GIF: 'image/gif',
  WEBP: 'image/webp',
  SVG: 'image/svg+xml',
  BMP: 'image/bmp',
  MP3: 'audio/mpeg',
  WAV: 'audio/wav',
  OGG: 'audio/ogg',
  AAC: 'audio/aac',
  FLAC: 'audio/flac',
  MP4: 'video/mp4',
  WEBM: 'video/webm',
  JSON: 'application/json',
  BINARY: 'application/octet-stream',
  TEXT: 'text/plain',
  HTML: 'text/html',
  CSS: 'text/css',
  JS: 'application/javascript',
} as const

export function mimeFromPath(path: string): MimeType {
  const ext = path.split('.').pop()?.toLowerCase() ?? ''
  switch (ext) {
    case 'png':  return 'image/png'
    case 'jpg':
    case 'jpeg': return 'image/jpeg'
    case 'gif':  return 'image/gif'
    case 'webp': return 'image/webp'
    case 'svg':  return 'image/svg+xml'
    case 'bmp':  return 'image/bmp'
    case 'mp3':  return 'audio/mpeg'
    case 'wav':  return 'audio/wav'
    case 'ogg':  return 'audio/ogg'
    case 'aac':  return 'audio/aac'
    case 'flac': return 'audio/flac'
    case 'mp4':  return 'video/mp4'
    case 'webm': return 'video/webm'
    case 'json': return 'application/json'
    case 'txt':  return 'text/plain'
    case 'html': return 'text/html'
    case 'css':  return 'text/css'
    case 'js':
    case 'mjs': return 'application/javascript'
    default:     return 'application/octet-stream'
  }
}