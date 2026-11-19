# 🎵 AquaMoon (水月音) v1.0.9 正式发布

> **水墨禅意 · Android 现代音乐播放器**
> *A modern music player blending Zen ink aesthetics with an industrial-grade audio core.*

本次更新为 **界面体验重构与全链路性能优化专项版本**：统一水墨丹青视觉体系与播放舞台交互，并对渲染合成、状态匹配、存储与扫描管线、Android 原生通知栏进行系统级治理。

---

## ✨ v1.0.9 核心更新亮点

### 🎨 1. 水墨视觉系统与交互升级
- **品牌徽标与动态音浪**：新增 `AquaMoonMark` 水墨印章徽标与 `PlayingWaveIndicator` 动态声波，统一各页 `EmptyStateView` 空状态引导。
- **沉浸播放舞台升级**：`FullPlayerPage` 移动端顶部增加「封面 / 歌词」切换胶囊与双行同步歌词预览，宽屏支持双栏歌词分栏舞台；`MiniPlayer` 支持左右轻扫快速切歌，深色模式卡片补齐微暖/微冷极细亮边。
- **提示与主题遵循**：`AppToast` 统一采用当前配色方案的 `snackBarBackground` 印色，消除硬编码底色割裂感；配色设置页展示全部 6 套主题配色并支持直观切换预览。

### ⚡ 2. 渲染与 GPU 帧率治理
- **动画与离屏图层优化**：`PlayingWaveIndicator` 使用 `RepaintBoundary` 隔离并用 `Transform.scale(scaleY)` 替代每帧改高重排；`HomePage` 使用 `TickerMode` 冻结离屏标签帧动画。
- **分级毛玻璃保真**：保留 `MiniPlayer`、移动底栏与单颗悬浮胶囊的实时磨砂，`GlassContainer` 新增 `enableBlur` 开关，对歌单网格卡快播按钮与大尺寸可滚动底部弹层（播放队列、统计下钻、添加歌曲等）切换轻量宣纸实色表面。
- **歌词滚屏无卡顿**：移除 `LyricsView` 与歌词预览卡全视口 `ShaderMask` 离屏 `saveLayer`，改用顶部/底部轻量渐变遮罩；把 ~5Hz 逐字卡拉 OK 订阅下沉至单行叶子组件并缓存 grapheme 切片。
- **全量精确监听与统计轻量化**：清理视图层 `MediaQuery.of` 为精确 `sizeOf` / `paddingOf` / `viewInsetsOf`；`ListeningHeatmap` 移除 365+ 份 eager `Tooltip` 改以轻量格子加点选详情；长列表与重绘隔离补齐，释放滑动阶段 GPU 与主线程余量。

### 🧠 3. 状态派生、匹配算法与存储扫描管线
- **跨源匹配与关联加速**：重构 `SongMatcher` 归一化路径为单遍码点扫描并预编译正则；`LocalSongLinkDialog` 加入 200ms 搜索防抖、候选结果与打分预缓存，移除 `shrinkWrap` 恢复列表虚拟化。
- **减少无效级联刷新**：补齐 `PlaybackProgress`、`QQMusicConfig`、`QQMusicCloudStatsSummary` 与 `QQMusicFavoritesState` 全字段值相等性，批量同步本地升级曲目（`updateSongsMerged`），`ListeningStatsTracker` 从每秒空转轮询改为 15s 定时器配合时间戳精确结算；各统计/收藏/发现页/设置页改用细粒度 `.select(...)` 与局部 `Consumer`。
- **存储压缩、热索引与批扫描**：`playback_queue` 采用 `gzip+json` 压缩存储与防抖合并落盘（保持完整歌曲快照与备份兼容性），播放进度写盘放宽为 12s 周期，`audio_service` 跨进程 `queue` 改为围绕当前曲目的 `±25` 滑动窗口；冷启动封面缓存迁移增加完成标记；`MetadataExtractor` 改用 64KB 探测头 + 按需随机读 + 层级式 MP4 原子遍历，批扫描合并进少批次 Isolate 并发池，并在已写盘缓存后自动清零 `albumArtBytes` 防内存膨胀。

### 🔔 4. Android 原生通知栏与稳定性加固
- **通知栏性能治理**：`CustomNotificationManager` 在保留每秒进度刷新的同时，将 5 个操作 `PendingIntent` 设为 `by lazy` 复用，对相同秒级状态早退；封面按 `inSampleSize` 降采样至 `≤ 256px` 绘制圆角后即刻 `recycle()`，并用单线程 `ExecutorService` + 代际校验 + 30s 失败退避取代裸线程并发拉图。
- **在线歌词匹配去重**：合并并发触发的同一首在线歌词检索与写库请求，避免组件释放后越界写入。

---

## 📦 安装与下载（仅 Android）

发布流水线只构建以下三个 Android 安装包：

| 安装包 | 适用设备 | 说明 |
| :--- | :--- | :--- |
| 🤖 `AquaMoon-Android-arm64-v8a.apk` | 绝大多数现代 64 位 Android 手机 | **推荐**，体积最小 |
| 🤖 `AquaMoon-Android-armeabi-v7a.apk` | 老旧 32 位 ARM 设备 | 兼容性优先 |
| 🤖 `AquaMoon-Android-Universal.apk` | 全部架构（含 x86_64 模拟器） | 通用包，体积稍大 |

> 覆盖安装即可保留曲库、歌单、统计记录与 QQ 音乐绑定信息。

> iOS / macOS / Windows / Linux / Web 版本不再随 Releases 发布；如需使用请在本地自行编译（见仓库 README 的「打包构建」章节）。

---

**Full Changelog**: https://github.com/e69d8e/AquaMoon/compare/v1.0.8...v1.0.9
