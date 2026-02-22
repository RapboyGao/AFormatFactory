# AFormatFactory Tauri App

## Tech Stack
- Tauri 2 (Rust backend)
- Vue 3 + TypeScript
- Vuetify 3 (dark theme enabled by default)
- Pinia + Vue Router
- pnpm

## Run
```bash
cd /Users/albert/Documents/AFormatFactory/tauri-app
pnpm install
pnpm tauri:dev
```

## Build frontend only
```bash
cd /Users/albert/Documents/AFormatFactory/tauri-app
pnpm build
```

## Architecture
- Frontend: `/Users/albert/Documents/AFormatFactory/tauri-app/src`
- Tauri backend: `/Users/albert/Documents/AFormatFactory/tauri-app/src-tauri/src`
- FFmpeg C API bridge (existing project code, reused):
  - `/Users/albert/Documents/AFormatFactory/Sources/AFormatFactoryFFmpegC/AFormatFactoryFFmpegC.c`
  - `/Users/albert/Documents/AFormatFactory/Sources/AFormatFactoryFFmpegC/AFormatFactoryFFmpegC_MediaEdit.c`
  - `/Users/albert/Documents/AFormatFactory/Sources/AFormatFactoryFFmpegC/AFormatFactoryFFmpegC_Probe.c`

## Implemented feature mapping
- Video conversion workspace
- Audio conversion workspace
- Media edit workspace (metadata/chapter/extra audio/subtitle)
- Task queue workspace (start/cancel/delete/clear completed/concurrency)
- App logs workspace
- Capability detection from FFmpeg C core
- Structured task progress (ratio/time/frame/speed/bitrate)

## Notes
- Backend execution path uses the FFmpeg C API bridge; not `Process + ffmpeg` shell execution.
- Current link mode is static link against `/Users/albert/Documents/AFormatFactory/ThirdParty/ffmpeg-install/lib`.
