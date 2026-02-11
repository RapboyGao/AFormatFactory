# AFormatFactory (macOS)

基于 SwiftUI + FFmpeg 的简易格式工厂。

## 功能
- 批量选择输入文件
- 选择输出目录
- 选择输出格式（MP4 / MOV / MKV / MP3 / WAV / GIF）
- 调用 FFmpeg 转码并显示日志

## 环境
- macOS 13+
- Xcode 15+
- 已安装 FFmpeg

```bash
brew install ffmpeg
```

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
