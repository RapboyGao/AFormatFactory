# AFormatFactory (macOS)

基于 SwiftUI + FFmpeg 的简易格式工厂。

## 功能
- 批量选择输入文件
- 选择输出目录
- 选择输出格式（按内置 ffmpeg 实际能力动态显示）
- 调用 FFmpeg 转码并显示日志
- 不依赖系统 FFmpeg：仅使用应用内 FFmpeg（二进制缺失时自动下载）
- 高级参数可调：视频 CRF/码率/FPS，音频码率/采样率/声道，覆盖同名文件开关
- 新增：编码器选择（自动/H.264/H.265/AV1）、分辨率缩放（原始/4K/2K/1080p/720p/480p）、参数预设（高质量/均衡/小体积）

## 环境
- macOS 13+
- Xcode 15+
- 网络可用（首次下载应用内 FFmpeg 时需要）

## 开发运行

```bash
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

## FFmpeg 来源说明
- 打包时会自动下载并内置到：`AFormatFactory.app/Contents/Resources/bin/ffmpeg`
- 运行时若检测不到该文件，会自动在线下载到应用目录后再执行转码
- 转码流程不会使用系统路径（`/opt/homebrew/bin/ffmpeg` 等）
