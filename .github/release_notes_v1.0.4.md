# 🎵 AquaMoon (水月音) v1.0.4 正式发布

> **水墨禅意 · 跨平台现代音乐播放器**
> *A modern, cross-platform music player blending Zen ink aesthetics with an industrial-grade audio core.*

本次更新为 **在线多源数据检索与校准功能的专项修复版**，解决了「搜不到 QQ 音乐数据」「网易云与 Apple Music 搜不到歌曲封面」等问题，并将下载目录与品牌文案全面统一为 AquaMoon。

---

## ✨ v1.0.4 核心更新亮点

### 🔧 1. 在线多源检索修复 — QQ 音乐恢复可用
- QQ 音乐原搜索接口（`client_search_cp`）已在服务端失效（HTTP 500），本次迁移至官方桌面端 `musicu.fcg` 网关，搜索结果恢复完整：曲名、歌手、专辑、时长、高清封面与 LRC 歌词全部可用。

### 🖼️ 2. 歌曲封面恢复 — 网易云 / Apple Music
- **网易云音乐**：官方搜索接口已不再返回专辑 `picUrl`，现改为基于专辑 `picId` 本地推导封面 CDN 地址（零额外请求），封面重新正常显示与下载。
- **Apple Music**：iTunes 中国区商店接口当前返回空结果，新增台湾区自动回退查询，中文歌曲封面恢复可用。

### ⏱️ 3. LRCLIB 时长校准修复
- 修复时长换算的运算符优先级问题（秒被当作毫秒存储），LRCLIB 候选的时长显示与匹配打分恢复正常，候选排序更精准。

### 🏷️ 4. 品牌统一 — SoundCraft → AquaMoon
- 封面 / 歌词的下载保存目录统一更名为 `AquaMoon`，全部保存提示文案同步更新。
- macOS 产品名同步为「水月音.app」，与工程配置保持一致。

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

