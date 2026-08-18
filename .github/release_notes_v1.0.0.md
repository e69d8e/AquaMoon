# 🎵 AquaMoon (水月音) v1.0.0 正式发布

> **水墨禅意 · 跨平台现代音乐播放器**  
> *A modern, cross-platform music player blending Zen ink aesthetics with an industrial-grade audio core.*

很高兴向大家宣布 **AquaMoon (水月音) v1.0.0** 首个正式版发布！AquaMoon 融合了东方水墨禅意美学与工业级稳健的音频架构，致力于在全平台提供沉浸、纯粹、丝滑的听歌体验。

---

## ✨ 核心特性亮点

### 🎨 1. 水墨禅意与现代交互美学
- **双模播放视觉**：
  - **黑胶唱片模式**：具备真实物理唱针落针/抬起切歌动效与平滑旋转唱片。
  - **高清大图封面模式**：沉浸式卡片呈现，支持手势缩放与高质感光影。
- **动态流光氛围背景**：基于歌曲专辑封面实时提取主色调，生成自适应玻璃拟态渐变背景。
- **响应式双端适配**：
  - **桌面端**（macOS / Windows / Linux / Web）：自适应 `NavigationRail` 与宽屏多列曲库布局。
  - **移动端**（Android / iOS）：流体响应式 `NavigationBar` 与手势友好交互。
- **全局常驻 Mini 播放器**：支持进度实时拖动、手势上滑展开全屏播放器。
- **动态律动动效**：歌曲列表与播放页内置精致的实时音频均衡器律动指示器。

### 🎧 2. 工业级音频播放核心
- **核心架构**：基于 `just_audio` + `audio_service` + `audio_session` 黄金三角构建。
- **系统级媒体控制**：
  - **Android**：深度适配系统媒体通知栏、锁屏控制器（含专辑封面、播放/暂停、切歌、进度条拖拽 Seek）。
  - **iOS / macOS**：原生集成 `MPRemoteCommandCenter` 与 `MPNowPlayingInfoCenter`，支持耳机线控、系统控制中心与触控栏控制。
- **音频焦点与中断智能管理**：
  - 来电、导航语音等打断事件发生时自动暂停或降音，结束后平滑恢复。
  - **防外放机制（Noisy Protection）**：拔出耳机或断开蓝牙耳机时即刻暂停，避免公共场合尴尬与炸耳。
- **4 种播放循环模式**：顺序播放、列表循环、单曲循环、随机播放。
- **无级倍速与音量调节**：0.5x ~ 2.0x 无级播放倍速变速播放与精准音量平衡。
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

### ⚡ 6. 毫秒级极速持久化
- 基于轻量级高性能键值数据库 **Hive**，实现本地曲库、歌单、红心收藏、历史记录与用户偏好的极速加载与零延迟读写。

---

## 📦 各平台安装与使用指引

| 平台 | 推荐安装包 | 说明与安装方法 |
| :--- | :--- | :--- |
| 🪟 **Windows** | `AquaMoon-Windows-x64-Setup.exe` | **推荐**：Inno Setup 标准向导安装程序，包含开始菜单与桌面快捷方式。亦可下载 `AquaMoon-Windows-x64-Portable.zip` 便携免安装版。 |
| 🍎 **macOS** | `AquaMoon-macOS.dmg` | **推荐**：双击打开 DMG 磁盘镜像，将 `水月音.app` 拖入 `Applications` 文件夹即可完成安装。亦提供 `AquaMoon-macOS.zip`。 |
| 🍎 **iOS** | `AquaMoon-iOS-Unsigned.ipa` | 支持 **TrollStore（巨魔商店）** 免越狱直接安装；或使用 **AltStore / Sideloadly / 爱思助手 / 牛蛙助手** 用普通 Apple ID 进行 7 天免费自签侧载安装。 |
| 🐧 **Linux** | `AquaMoon-Linux-x64.deb` | **推荐**：适用于 Ubuntu / Debian / Deepin / UOS 等系统，双击或运行 `sudo dpkg -i AquaMoon-Linux-x64.deb` 即可安装。亦提供 `AquaMoon-Linux-x64.tar.gz` 便携版。 |
| 🤖 **Android** | `AquaMoon-Android-arm64-v8a.apk` | **推荐**：适用于绝大多数现代 64 位主流 Android 手机（体积更小）。其他设备可选通用版 `AquaMoon-Android-Universal.apk`，Google Play 可用 `AquaMoon-Android.aab`。 |
| 🌐 **Web** | `AquaMoon-Web.zip` | Web SPA 静态部署资源包，解压后可直接部署至 Nginx / GitHub Pages / Cloudflare Pages / Vercel 等托管平台。 |

---

<div align="center">
Made with ❤️ by AquaMoon Team
</div>
