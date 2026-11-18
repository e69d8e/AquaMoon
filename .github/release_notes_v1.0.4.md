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

---

## 📦 安装与下载（仅 Android）

发布流水线只构建以下三个 Android 安装包：

| 安装包 | 适用设备 | 说明 |
| :--- | :--- | :--- |
| 🤖 `AquaMoon-Android-arm64-v8a.apk` | 绝大多数现代 64 位 Android 手机 | **推荐**，体积最小 |
| 🤖 `AquaMoon-Android-armeabi-v7a.apk` | 老旧 32 位 ARM 设备 | 兼容性优先 |
| 🤖 `AquaMoon-Android-Universal.apk` | 全部架构（含 x86_64 模拟器） | 通用包，体积稍大 |

> iOS / macOS / Windows / Linux / Web 版本不再随 Releases 发布；如需使用请在本地自行编译（见仓库 README 的「打包构建」章节）。

---

**Full Changelog**: https://github.com/e69d8e/AquaMoon/compare/v1.0.3...v1.0.4
