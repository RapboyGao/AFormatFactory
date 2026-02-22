# AFormatFactory (macOS)

基于 SwiftUI + FFmpeg 源码构建产物的简易格式工厂。

## 功能
- 批量选择输入文件
- 选择输出目录
- 选择输出格式（按内置 ffmpeg 实际能力动态显示）
- 调用 FFmpeg 转码并显示日志
- 不依赖系统 FFmpeg：使用项目内 `ThirdParty/ffmpeg` 源码本地构建产物
- 高级参数可调：视频 CRF/码率/FPS，音频码率/采样率/声道，覆盖同名文件开关
- 新增：编码器选择（自动/H.264/H.265/AV1）、分辨率缩放（原始/4K/2K/1080p/720p/480p）、参数预设（高质量/均衡/小体积）
- 任务队列：一次可添加多个文件（每个源文件生成独立任务），每个任务独立日志，并支持多任务并发执行

## 环境
- macOS 13+
- Xcode 15+
- 首次同步 FFmpeg 源码时需网络

## 开发运行

```bash
./Scripts/build_ffmpeg_libs.sh
swift run
```

## 打包为标准 `.app`

```bash
./Scripts/build_app.sh
```

产物位置：`dist/AFormatFactory.app`

可直接双击运行，或：

```bash
open dist/AFormatFactory.app
```

## 签名配置
默认使用 ad-hoc 签名（`SIGN_IDENTITY=-`），适合本机开发测试。

使用开发者证书签名：

```bash
SIGN_IDENTITY="Apple Development: Your Name (TEAMID)" ./Scripts/build_app.sh
```

自定义 Bundle ID / 版本号：

```bash
BUNDLE_ID="com.yourcompany.aformatfactory" APP_VERSION="1.0.0" BUILD_NUMBER="1" ./Scripts/build_app.sh
```

跳过签名：

```bash
SIGN_APP=0 ./Scripts/build_app.sh
```

## 图标
- 默认会在首次打包时自动生成 `Assets/AppIcon.icns`。
- 你也可以手动替换该文件后重新打包。

## FFmpeg 来源与许可
- FFmpeg 源码位于：`ThirdParty/ffmpeg/source`（固定 tag，见 `ThirdParty/ffmpeg/VERSION.txt`）
- 本地构建产物位于：`ThirdParty/ffmpeg-install`
- App 不再内置 `ffmpeg` 可执行文件，运行时通过静态链接 `libav*` 调用
- 默认构建策略：`LGPL 优先（--disable-gpl --disable-nonfree）`
- 同步源码：
```bash
./Scripts/sync_ffmpeg_source.sh
```


---

# AFormatFactory Tauri App

## Tech Stack
- Tauri 2 (Rust backend)
- Vue 3 + TypeScript
- Vuetify 3 (dark theme enabled by default)
- Pinia + Vue Router
- pnpm

## Unified Build Targets
- macOS: supports both `tauri` and `swiftui` targets.
- Non-macOS: supports `tauri` target only.

Use unified scripts:
```bash
pnpm run build:target:tauri
pnpm run build:target:swiftui
pnpm run build:target:all
```

Or call wrappers in `Scripts/`:
```bash
./Scripts/build_target.sh tauri
./Scripts/build_target.sh swiftui
./Scripts/build_target.sh all
```

Windows wrapper:
```bat
Scripts\build_target.bat tauri
```

## Run
```bash
pnpm install
pnpm tauri:dev
```

## Build frontend only
```bash
pnpm build
```

## Architecture
- Frontend: `/Users/albert/Documents/AFormatFactory/vue`
- Tauri backend: `/Users/albert/Documents/AFormatFactory/src-tauri/src`
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
