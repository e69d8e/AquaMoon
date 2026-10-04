# 🎵 AquaMoon (水月音) v1.0.3 正式发布

> **水墨禅意 · 跨平台现代音乐播放器**  
> *A modern, cross-platform music player blending Zen ink aesthetics with an industrial-grade audio core.*

很高兴向大家宣布 **AquaMoon (水月音) v1.0.3** 正式发布！本次更新带来了全新的 **GitHub Release 自动检查更新**与**每首歌曲播放次数统计**，并修复了播放页手势冲突、精简了首页交互，进一步收敛了冗余重建，让播放器更快、更稳、更省心。

---

## ✨ v1.0.3 核心更新亮点

### 🔄 1. GitHub Release 检查更新
- **自动检查更新**：应用启动后静默检查 GitHub 最新 Release，发现新版本时弹窗展示更新说明，一键「前往下载」直达 Release 页面。
- **24 小时节流**：自动检查每 24 小时最多发起一次，失败保持静默，绝不打扰。
- **手动检查入口**：设置 →「检查更新」，实时显示当前版本；检查中、已是最新、网络异常三种状态均有明确反馈。
- **开关自由掌控**：设置中可随时开启 / 关闭自动检查，选择权交还用户。
- **语义化版本比较**：正确处理 `v` 前缀、build 号（`1.0.2+3`）与预发布标签，预发布版本不会误报为更新。

### 📊 2. 每首歌曲播放次数统计与展示
- 曲库列表直接展示每首歌曲的累计播放次数，高频曲目一目了然。

### 🎨 3. 播放与交互体验优化
- **修复播放页手势冲突**：解决封面与歌词之间滑动切换的冲突问题，以及歌词页重放时的滚动异常。
- **首页交互精简**：次要功能收入二级菜单，主界面更聚焦于曲库、歌单与收藏。

### ⚡ 4. 性能优化
- **收敛播放进度与统计数据的冗余重建**：高频播放进度流不再触发无关组件级联重建，长时播放更流畅、更省电。

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

