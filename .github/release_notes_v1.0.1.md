# 🎵 AquaMoon (水月音) v1.0.1 正式发布

> **水墨禅意 · 跨平台现代音乐播放器**  
> *A modern, cross-platform music player blending Zen ink aesthetics with an industrial-grade audio core.*

很高兴向大家宣布 **AquaMoon (水月音) v1.0.1** 正式发布！本次更新带来了全新的**全景听歌数据统计分析系统**，并对全工程的状态流、数据持久化与 I/O 链路进行了深度的**性能重构与流过滤优化**，同时建立了覆盖核心业务的完整**单元与组件测试套件**。

---

## ✨ v1.0.1 核心更新亮点

### 📊 1. 全景听歌数据统计与多维分析系统
- **四维时间周期切换**：支持按「日」、「周」、「月」、「年」自由切换听歌历史与播放偏好。
- **直观动态图表 (`ListeningChart`)**：
  - 24 小时峰值时段分析：精确显示全天最常听歌的时间段分布。
  - 柱状统计图高亮与单柱点击详情联动，直观呈现收听走势。
- **听歌深度分析与排行榜**：
  - 统计卡片：清晰汇总收听总时长、总播放次数、独立曲目数、独立歌手数以及日均听歌时长。
  - **Top 排行榜**：分别呈现当前周期内「最常听单曲 Top 排行」与「最常听歌手 Top 排行」，包含播放次数与累计收听秒数。
- **轻量低功耗后台追踪器 (`ListeningStatsTracker`)**：
  - 分钟级聚合缓冲，避免高频写盘与电量消耗。
  - 听歌进度与时长自动持久化入库，跨会话无缝累加。

---

### ⚡ 2. 深度性能优化与响应速度跃升
- **响应式状态订阅精准解耦 (Selector Granularity)**：
  - `filteredSongsProvider`、`favoritesSongsProvider`、`historySongsProvider` 及歌单/播放器组件改用 `.select((s) => s.songs)` 粒度监听。
  - 彻底消除了音乐扫描、文件夹导入及在线元数据匹配过程中高频进度通知（`scanProgressText` / `scanProgressPercent`）对歌曲列表造成的无谓全量过滤、重复排序与主界面卡顿。
  - 移除了全屏播放器顶级无意义全局 watch，隔绝歌词加载和解析对全屏播放器背景和唱片组件的级联重绘。
- **内存差量即时同步 (Differential In-Memory Sync)**：
  - 重构了曲库单曲收藏（`toggleFavorite`）、信息编辑（`updateSong`）与单曲移除（`deleteSong`），以及歌单的所有修改操作。
  - 告别全量重读磁盘数据库与 $O(N)$ 重复去重，全面升级为 $O(1)$ 内存差量更新，界面交互零延迟。
- **I/O 与垃圾回收 (GC) 加固**：
  - `MetadataExtractor.extractFromFile` 改用 `BytesBuilder(copy: false)` 流式组装文件头部字节，消除了大文件扫描时的连续动态数组扩容与垃圾回收抖动。
  - 封面本地缓存增加命中比对校验，若已有缓存命中直接复用，杜绝重复写入磁盘。
  - `LyricsView` 增加了切歌生命周期感知，切歌时重置滚动状态并释放历史 `GlobalKey`，消除潜在内存泄漏风险。

---

### 🧪 3. 自动化测试套件与代码健壮性保障
- 构建了覆盖核心领域模型与视图状态的单元测试与 Widget 测试套件：
  - `test/library_notifier_test.dart`：曲库去重、内存差量更新、多规则检索排序、性能隔离验证。
  - `test/playlist_notifier_test.dart`：歌单完整生命周期、增删曲目、封面设置、收藏与历史衍生。
  - `test/audio_handler_queue_test.dart`：队列重排、索引同步、循环模式轮转与边界保障。
  - `test/performance_and_widget_test.dart`：`SongArtwork`、`CustomProgressBar`、`SongTile` 核心组件渲染与交互验证。
- 自动化测试用例数扩充至 **59 项（100% 通过）**，代码静态分析保持 **0 错误、0 警告**。

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

