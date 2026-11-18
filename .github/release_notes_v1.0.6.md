# 🎵 AquaMoon (水月音) v1.0.6 正式发布

> **水墨禅意 · 跨平台现代音乐播放器**
> *A modern, cross-platform music player blending Zen ink aesthetics with an industrial-grade audio core.*

本次更新为 **界面质感的专项升级**：迷你播放器与全局底部弹层全面磨砂玻璃化，界面更通透、更有层次。

---

### 📋 版本发布信息

- **版本号**：`v1.0.6`（构建版本 `1.0.6+7`）
- **发布日期**：2026-10-05
- **Git 标签**：`v1.0.6` (`ef9c93a`)
- **发布地址**：[GitHub Releases v1.0.6](https://github.com/e69d8e/AquaMoon/releases/tag/v1.0.6)
- **代码对比**：[`v1.0.5...v1.0.6`](https://github.com/e69d8e/AquaMoon/compare/v1.0.5...v1.0.6)
- **完整提交记录**：[`commits/v1.0.6`](https://github.com/e69d8e/AquaMoon/commits/v1.0.6)

---

## ✨ v1.0.6 核心更新亮点

### 🪟 1. 播放器磨砂玻璃化
- **迷你播放器去除描边**，改为半透明磨砂玻璃质感：列表滚动时，封面与列表色彩在玻璃后若隐若现，播放器与内容融为一体。
- **移动端底部导航栏同步磨砂化**：曲库/歌单/收藏的内容从导航栏与迷你播放器下方平滑滚过，底部区域整体更通透、更有纵深感。

### 🧊 2. 底部弹层全面磨砂化
- **播放队列**、**睡眠定时器**、**歌手收听明细**、**歌单选择封面**、**歌单添加歌曲**、**在线检索结果详情** 共 6 个底部弹层全部改为毛玻璃质感，弹出时背后的页面被柔和虚化，视觉焦点更集中。

### 🎨 3. 全配色自适应
- 磨砂底色与模糊强度均取自当前配色主题，六套配色（水墨丹青 / 青花瓷 / 青竹 / 暮山紫 / 琥珀 / 黛青）与深浅色模式全部自动适配，无需手动调整。

---

## 📦 安装与下载（仅 Android）

发布流水线只构建以下三个 Android 安装包：

| 安装包 | 适用设备 | 说明 |
| :--- | :--- | :--- |
| 🤖 `AquaMoon-Android-arm64-v8a.apk` | 绝大多数现代 64 位 Android 手机 | **推荐**，体积最小 |
| 🤖 `AquaMoon-Android-armeabi-v7a.apk` | 老旧 32 位 ARM 设备 | 兼容性优先 |
| 🤖 `AquaMoon-Android-Universal.apk` | 全部架构（含 x86_64 模拟器） | 通用包，体积稍大 |

> iOS / macOS / Windows / Linux / Web 版本不再随 Releases 发布；如需使用请在本地自行编译（见仓库 README 的「打包构建」章节）。
