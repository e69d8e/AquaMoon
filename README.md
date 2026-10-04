<div align="center">

<img src="assets/icons/app_icon.png" alt="AquaMoon Logo" width="128" height="128" style="border-radius: 24px; box-shadow: 0 8px 24px rgba(0,0,0,0.15);" />

# AquaMoon (水月音) 🎵

**水墨禅意 · 跨平台现代音乐播放器**

*A modern, cross-platform music player blending Zen ink aesthetics with an industrial-grade audio core.*

[![Flutter](https://img.shields.io/badge/Flutter-3.x-02569B?style=for-the-badge&logo=flutter&logoColor=white)](https://flutter.dev)
[![Dart](https://img.shields.io/badge/Dart-3.x-0175C2?style=for-the-badge&logo=dart&logoColor=white)](https://dart.dev)
[![Platform](https://img.shields.io/badge/Platform-Android%20%7C%20iOS%20%7C%20macOS%20%7C%20Windows%20%7C%20Linux%20%7C%20Web-blue?style=for-the-badge)](https://github.com/e69d8e/AquaMoon)
[![CI](https://img.shields.io/github/actions/workflow/status/e69d8e/AquaMoon/ci.yml?branch=main&style=for-the-badge&label=CI)](https://github.com/e69d8e/AquaMoon/actions)
[![Release](https://img.shields.io/github/v/release/e69d8e/AquaMoon?style=for-the-badge&color=success)](https://github.com/e69d8e/AquaMoon/releases)
[![License](https://img.shields.io/badge/License-MIT-green?style=for-the-badge)](LICENSE)

</div>

---

## 📖 简介 / Overview

**AquaMoon (水月音)** 是一款基于 Flutter 构建的现代化、高性能、跨平台音乐播放器。

它不仅拥有水墨禅意、极简克制的现代视觉美学，更具备工业级稳固的音频核心架构，支持系统级媒体控制、智能歌词与封面匹配、在线音乐检索试听、本地全格式元数据解析及 GitHub Actions 全平台全架构自动化构建发布。

---

## ✨ 核心特性 / Features

### 🎨 1. 水墨禅意与现代交互美学
- **双模播放视觉**：
  - **黑胶唱片模式**：具备真实的物理唱针切歌落针/抬起动效与平滑旋转唱片。
  - **高清大图封面模式**：沉浸式卡片呈现，支持实时缩放与手势交互。
- **动态流光氛围背景**：根据歌曲专辑封面智能提取主色调，生成自适应玻璃拟态渐变背景。
- **自适应响应式布局**：
  - **桌面端**（macOS / Windows / Linux / Web）：自适应 `NavigationRail` 与宽屏多列曲库布局。
  - **移动端**（Android / iOS）：流体响应式 `NavigationBar` 与手势友好交互。
- **全局常驻 Mini 播放器**：支持进度实时滑动、手势拖拽快速展开全屏播放器。
- **动态律动动效**：列表与播放页内置精致的实时音频均衡器律动指示器。

### 🎧 2. 工业级音频播放核心
- **核心架构**：基于 `just_audio` + `audio_service` + `audio_session` 黄金三角构建。
- **系统级媒体控制**：
  - **Android**：深度适配系统媒体通知栏、锁屏控制器（含专辑大图、播放/暂停、上一曲/下一曲、进度条拖拽 Seek）。
  - **iOS / macOS**：原生集成 `MPRemoteCommandCenter` 与 `MPNowPlayingInfoCenter`，支持耳机线控、系统控制中心与触控栏控制。
- **音频焦点与中断智能管理**：
  - 来电、导航语音等打断事件发生时自动暂停或降音，结束后平滑恢复。
  - **防外放机制（Noisy Protection）**：拔出耳机或断开蓝牙耳机时即刻暂停，避免公共场合尴尬与炸耳。
- **4 种播放循环模式**：顺序播放、列表循环、单曲循环、随机播放。
- **无级倍速与音量调节**：0.5x ~ 2.0x 无级播放倍速变速播放与精准音量控制。
- **动态播放队列**：支持拖拽重排序、单曲移除、批量清空与快速插播。

### 📜 3. 智能歌词与高清封面中枢
- **双引擎在线匹配**：对接开放标准 **LRCLIB** 国际歌词库与 **网易云开放接口**。
- **智能降噪清洗**：内置智能清洗管道，自动过滤歌曲标题中的 `[FLAC]`、`(Hi-Res)`、`[320k]`、`HQ` 等无用后缀与音质标签，极大提升匹配率。
- **毫秒级同步滚动歌词**：
  - 支持标准 `[mm:ss.xx]` 及逐字时间轴解析。
  - 当前句居中平滑自动滚动，高亮放大显示。
  - **点击任意一行歌词直接 Seek 跳转至对应位置播放**。
- **歌词与封面导出**：支持歌词一键复制到剪贴板、导出为本地 `.lrc` 文件以及重新检索与高清封面缓存。

### 🔍 4. 在线音乐检索与即时试听
- 支持在线全局搜索歌曲、艺术家、专辑。
- 在线即点即播试听，自动拉取在线歌词与高清封面。
- 支持将心仪的在线歌曲一键收藏或加入本地自定义歌单。

### 📁 5. 本地全格式解析与高速扫描
- **纯 Dart 高性能元数据提取器**：
  - 支持 **ID3v1 / ID3v2 (ID3v2.2, ID3v2.3, ID3v2.4)** 解析。
  - 支持 **FLAC Vorbis Comment** 及内嵌 **APIC** 高清封面提取。
  - 即使缺失 ID3 标签，也能从标准文件名（如 `歌手 - 歌名.mp3`）智能兜底提取。
- **广泛音频格式支持**：`.mp3`, `.flac`, `.m4a`, `.wav`, `.aac`, `.ogg` 等。
- **多维度导入**：支持单曲/多选文件导入与指定文件夹递归批量扫描。

### ⚙️ 6. 系统播放器个性化配置
- 专门提供系统媒体播放器通知栏 UI 定制界面，可按需定制系统播放通知中的操作按钮、封面展示与交互行为。

### ⚡ 7. 毫秒级极速持久化
- 基于轻量级高性能键值数据库 **Hive**，实现本地曲库、歌单、红心收藏、历史记录与用户偏好的极速加载与零延迟读写。

---

## 🛠️ 技术栈 / Tech Stack

| 模块 | 选型技术 / 库 |
| :--- | :--- |
| **核心框架** | Flutter 3.x / Dart 3.x |
| **状态管理** | Riverpod (`flutter_riverpod: ^2.6.1`) |
| **音频引擎** | `just_audio: ^0.10.6` |
| **系统后台服务** | `audio_service: ^0.18.19` |
| **音频焦点管理** | `audio_session: ^0.2.4` |
| **本地持久化** | `hive: ^2.2.3` + `hive_flutter: ^1.1.0` |
| **文件与权限** | `file_picker: ^12.0.0`, `permission_handler: 11.3.1`, `path_provider: ^2.1.6` |
| **网络与图片** | `http: ^1.6.0`, `cached_network_image: ^3.4.1`, `palette_generator: ^0.3.3+7` |
| **持续集成与发布** | GitHub Actions (全平台多架构矩阵构建) |

---

## 📂 项目架构 / Project Structure

```
lib/
├── main.dart                          # 应用主入口与 AudioService 全局初始化
├── app.dart                           # Material 3 全局主题、路由与外观配置
├── core/
│   ├── audio/
│   │   ├── audio_player_handler.dart  # AudioService & JustAudio 核心整合与事件分发
│   │   └── audio_session_coordinator.dart # 音频焦点、通话打断与 Noisy 耳机拔出处理
│   ├── theme/
│   │   └── app_theme.dart             # 水墨禅意主题配色、暗色/亮色规范与组件样式
│   └── utils/
│       ├── lrc_parser.dart            # LRC 时间轴解析、逐字标签清洗与二分法检索
│       ├── metadata_extractor.dart    # 纯 Dart ID3v1/ID3v2/FLAC 本地元数据与 APIC 封面解析
│       └── formatters.dart            # 时间、文件大小与字符格式化工具
├── models/
│   ├── song.dart                      # 歌曲数据模型 (Hive 序列化支持)
│   ├── lyric_line.dart                # 单行歌词时间戳与内容模型
│   ├── playlist.dart                  # 自定义歌单模型
│   ├── playback_mode.dart             # 播放循环模式枚举与状态机
│   └── playback_progress.dart         # 播放进度与缓冲模型
├── providers/
│   ├── audio_provider.dart            # 播放控制、倍速、音量与播放状态状态流
│   ├── library_provider.dart          # 本地曲库、文件扫描导入与检索 Provider
│   ├── playlist_provider.dart         # 歌单管理、红心收藏、播放历史 Provider
│   └── lyrics_provider.dart           # 实时歌词同步与当前高亮行匹配 Provider
├── services/
│   ├── storage_service.dart           # Hive 本地数据库读写层
│   ├── online_metadata_service.dart   # LRCLIB & 网易云开放接口歌词封面智能匹配引擎
│   └── file_export_service.dart       # 歌词导出、文件保存与剪贴板服务
└── views/
    ├── home/
    │   ├── home_page.dart             # 响应式主页 (自适应 NavigationRail / NavigationBar)
    │   └── tabs/                      # 全部歌曲 / 歌单 / 收藏 视图
    ├── player/
    │   ├── mini_player.dart           # 底部常驻迷你播放控制栏
    │   ├── full_player_page.dart      # 全屏播放器 (黑胶唱片 / 封面 / 控制台)
    │   └── lyrics_view.dart           # 实时同步滚动歌词组件 (支持点击 Seek 跳转)
    ├── online_search/
    │   └── online_search_page.dart    # 在线音乐搜索、试听与元数据匹配页面
    ├── playlists/
    │   └── playlist_detail_page.dart  # 歌单详情、排序与批量管理页面
    ├── settings/
    │   ├── settings_page.dart         # 系统设置与主题偏好页面
    │   └── notification_player_settings_page.dart # 系统媒体通知栏样式定制页面
    └── widgets/
        ├── song_artwork.dart          # 封面渲染器 (支持网络/本地文件/内存字节自适应)
        ├── song_tile.dart             # 歌曲列表项 (含均衡器律动、滑动菜单)
        └── custom_progress_bar.dart   # 精准进度拖动与时间预览控制条
```

---

## 🚀 快速开始 / Quick Start

### 环境依赖
- [Flutter SDK](https://flutter.dev/docs/get-started/install) >= 3.13.0 (推荐最新 Stable 版本)
- [Dart SDK](https://dart.dev/get-dart) >= 3.13.0
- 平台对应开发环境：
  - **Android**: Android Studio / Android SDK (API 21+)
  - **iOS / macOS**: Xcode 15+ & CocoaPods
  - **Windows**: Visual Studio 2022 (带 C++ 桌面开发套件)
  - **Linux**: `clang`, `cmake`, `ninja-build`, `pkg-config`, `libgtk-3-dev`, `liblzma-dev`, `libasound2-dev`

### 1. 克隆项目与安装依赖

```bash
git clone https://github.com/e69d8e/AquaMoon.git
cd AquaMoon

# 获取依赖
flutter pub get
```

### 2. 运行代码分析与单元测试

```bash
# 静态代码分析
flutter analyze

# 运行完整单元测试集
flutter test
```

### 3. 本地启动运行

```bash
# macOS
flutter run -d macos

# Android
flutter run -d <android-device-id>

# iOS
flutter run -d <ios-device-id>

# Windows
flutter run -d windows

# Linux
flutter run -d linux

# Web
flutter run -d chrome
```

---

## 📦 打包构建 / Build & Release

您可以使用以下命令在本地或借助 GitHub Actions 为各平台构建对应格式的安装与发布包：

### 🤖 Android (APK & AAB)
```bash
# 构建拆分架构的 APK (包体积更小)
flutter build apk --release --split-per-abi

# 构建通用全架构 APK
flutter build apk --release

# 构建 Google Play 上架 AppBundle
flutter build appbundle --release
```

### 🍎 iOS (IPA)
```bash
# 构建未签名 iOS App (用于 AltStore / TrollStore / Sideloadly 侧载自签)
flutter build ios --release --no-codesign
mkdir -p Payload && cp -r build/ios/iphoneos/Runner.app Payload/
zip -r -y AquaMoon-iOS-Unsigned.ipa Payload
```

### 🍎 macOS (.app / DMG / ZIP)
```bash
# 本地编译
flutter build macos --release

# 制作 DMG 磁盘映像 (包含拖拽到 Applications 快捷安装)
mkdir -p dmg_temp && cp -r build/macos/Build/Products/Release/*.app dmg_temp/
ln -s /Applications dmg_temp/Applications
hdiutil create -volname "AquaMoon" -srcfolder dmg_temp -ov -format UDZO AquaMoon-macOS.dmg
```

### 🪟 Windows (EXE 安装包 / 便携 ZIP)
```bash
# 本地编译
flutter build windows --release
# 可配合 Inno Setup (windows/installer/installer.iss) 编译一键安装向导 EXE 安装程序
```

### 🐧 Linux (.deb 安装包 / tar.gz)
```bash
# 本地编译
flutter build linux --release
# 支持打包为标准 Debian / Ubuntu / Deepin / UOS .deb 安装包以及便携 tar.gz
```

### 🌐 Web (ZIP)
```bash
flutter build web --release
# 产物位于 build/web/
```

---

## 🤖 GitHub Actions 自动化 CI/CD 与多格式全平台 Release

本项目已预配置全自动化的 GitHub Actions 工作流：

1. **持续集成 (CI)**：每次提交代码或提交 PR 时，自动触发代码规范分析 (`flutter analyze`) 与单元测试 (`flutter test`)。
2. **多格式全平台自动构建发布 (Release)**：
   - 当向仓库推送版本标签（如 `git tag v1.0.1 && git push origin v1.0.1`）时，会自动触发 `.github/workflows/release.yml`。
   - 自动在 GitHub Actions 云端并行编译并输出以下丰富格式产物：
     - 🤖 **Android**：`AquaMoon-Android-arm64-v8a.apk`, `AquaMoon-Android-armeabi-v7a.apk`, `AquaMoon-Android-Universal.apk`, `AquaMoon-Android.aab`
     - 🍎 **iOS**：`AquaMoon-iOS-Unsigned.ipa`（支持 TrollStore 免越狱直装、AltStore / Sideloadly / 爱思助手个人 Apple ID 7 天免费自签侧载）
     - 🍎 **macOS**：`AquaMoon-macOS.dmg`（内置 Applications 拖拽软链）与 `AquaMoon-macOS.zip`
     - 🪟 **Windows**：`AquaMoon-Windows-x64-Setup.exe`（Inno Setup 专业向导安装程序）与 `AquaMoon-Windows-x64-Portable.zip`
     - 🐧 **Linux**：`AquaMoon-Linux-x64.deb`（标准 deb 双击安装包）与 `AquaMoon-Linux-x64.tar.gz`
     - 🌐 **Web**：`AquaMoon-Web.zip`
   - 自动在 GitHub Releases 发布新版本并上传所有格式的安装包，附带自动生成的更新日志。

---

## 🔒 权限与各平台配置说明

- **Android (`AndroidManifest.xml`)**：
  - 声明 `FOREGROUND_SERVICE` 与 `FOREGROUND_SERVICE_MEDIA_PLAYBACK` 支持后台不中断音频播放。
  - 声明 `READ_MEDIA_AUDIO` / `READ_EXTERNAL_STORAGE` 权限用于本地曲库扫描。
  - 配置 `com.ryanheise.audioservice.AudioService` 前台服务。
- **iOS (`Info.plist`)**：
  - 开启 `UIBackgroundModes` 包含 `audio` 支持后台锁屏与控制中心播放。
  - 配置媒体库访问权限与本地文件访问描述。
- **macOS (`*.entitlements`)**：
  - 开启 `com.apple.security.network.client` 允许在线检索歌词与封面。
  - 开启 `com.apple.security.files.user-selected.read-write` 允许用户自由导入本地音乐文件夹与导出歌词。

---

## 📄 开源许可证 / License

本项目采用 [MIT License](LICENSE) 许可证开源。

