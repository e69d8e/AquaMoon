# 🎵 AquaMoon (水月音) v1.0.2 正式发布

> **水墨禅意 · 现代音乐播放器**
> *A modern music player blending Zen ink aesthetics with an industrial-grade audio core.*

本次更新聚焦 **正式发布签名**、**主题切换** 与 **性能优化**，同时重构了在线搜索与常用弹窗的交互。

---

## ✨ v1.0.2 核心更新亮点

### 🔐 1. 正式发布签名
- 接入正式 release keystore 签名，替换原先的 debug 签名回退；凭据支持本地 `android/key.properties` 与 CI 环境变量两种来源。
- 发布流水线从 Secrets 还原 keystore，并校验 APK 签名证书指纹，防止 debug 签名产物被误发布。

### 🌙 2. 主题与界面
- 新增 `ThemeMode` 持久化切换，深浅色选择随设置保存。
- 播放器、歌单、设置、统计页的界面细节统一调整。

### 🔎 3. 交互重构
- 在线搜索、候选曲目对话框、编辑歌曲弹窗重构，操作路径更短。

### ⚡ 4. 性能优化
- 元数据解析移入后台 isolate，扫描 / 导入曲库不再掉帧。
- 播放事件平台通道调用去重，消除播放中每秒多次无效通知刷新。
- MiniPlayer 移除 `BackdropFilter`，改善首页滚动流畅度。

### 🧹 5. 其它
- 移除未使用的 `palette_generator` 依赖。
- Linux DEB 版本号改为从 `pubspec.yaml` 读取，避免硬编码过期。
- 版本号 `1.0.1+2` → `1.0.2+3`。

## 🔗 完整提交记录

https://github.com/e69d8e/AquaMoon/commits/v1.0.2

---

## 📦 安装与下载（仅 Android）

发布流水线只构建以下三个 Android 安装包：

| 安装包 | 适用设备 | 说明 |
| :--- | :--- | :--- |
| 🤖 `AquaMoon-Android-arm64-v8a.apk` | 绝大多数现代 64 位 Android 手机 | **推荐**，体积最小 |
| 🤖 `AquaMoon-Android-armeabi-v7a.apk` | 老旧 32 位 ARM 设备 | 兼容性优先 |
| 🤖 `AquaMoon-Android-Universal.apk` | 全部架构（含 x86_64 模拟器） | 通用包，体积稍大 |

> iOS / macOS / Windows / Linux / Web 版本不再随 Releases 发布；如需使用请在本地自行编译（见仓库 README 的「打包构建」章节）。
