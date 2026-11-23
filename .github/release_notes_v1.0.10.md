# 🎵 AquaMoon (水月音) v1.0.10 正式发布

> **水墨禅意 · Android 现代音乐播放器**
> *A modern music player blending Zen ink aesthetics with an industrial-grade audio core.*

本次更新为 **全量 UI/UX 精修与无障碍体验专项版本**：系统性加固配色对比度、大字号与窄屏适配、键盘与读屏无障碍、动效偏好尊重及 Web 端兼容性，并修复歌单重命名与多选交互问题。

---

## ✨ v1.0.10 核心更新亮点

### 🎨 1. 全主题配色对比度与语义 Token 完善
- **WCAG AA 对比度达标**：调整 `bamboo`（竹林清风）、`inkwash.dark`（水墨丹青暗色）、`violet.dark`（紫陌花开暗色）、`amber.light`（暖阳秋意亮色）及全 6 套配色的三级文本 `textTertiary`，确保 12 组亮/暗组合在文字、图标与悬浮提示胶囊上均具备清晰辨识度。
- **语义色彩体系化**：在 `AppColors` 中补充 `success`、`warning`、`info` 语义令牌并强化未选中 `Switch`、描边及焦点/悬停视觉反馈，清理各页面硬编码颜色常量。

### 📐 2. 大字号缩放、窄屏适配与弹窗规范
- **自适应列表与网格**：移除曲库、收藏、歌单详情、最近播放、未匹配曲目、播放队列、添加歌曲与歌单网格卡片等处的固定 `itemExtent` 与刚性高度裁剪；在 `320px` 极窄屏与 `2.0x` 系统字体缩放下支持 `Wrap` 自动换行、动态网格行高与竖排 `SegmentedButton` 降级，避免文字截断或布局溢出。
- **标准化弹窗与安全焦点**：新增 `ui_helpers.dart`（`ModalSheetHeader`、`showDestructiveConfirmDialog`、`ActionPillButton`、`ResponsivePageContainer`、`CollapsibleSection`）；为底栏弹层统一显式关闭按钮，破坏性确认框统一将初始焦点置于安全「取消」项并用 `error` 语义突出高危操作。
- **模态友好的 Toast 反馈**：`AppToast` 支持最长 2 行换行、延长的阅读停留时长（2.4s / 3.6s）、显式关闭按钮、悬停暂停与 `liveRegion` 播报；在模态弹窗或底栏内触发时自动升至根 `Overlay` 置顶展示。

### ♿ 3. 无障碍语义、减弱动效与交互修复
- **减弱动态效果适配**：新增 `motionDuration` 助手并在各视图过渡动画、全屏播放页翻页、歌词滚动及 Web 启动底幕（`prefers-reduced-motion`）中统一响应系统减动效偏好。
- **键盘导航与焦点隔离**：在全部歌曲与收藏页顶栏折叠收起及均衡器总开关关闭时同步启用 `ExcludeFocus` / `ExcludeSemantics`；为 `MiniPlayer`、`FullPlayerPage`、统计图表、`ListeningHeatmap` 与设置的自定义卡片补充完整 `Semantics` 与更大的触控热区，全屏播放页支持 `Esc` 退出并移除封面背景误触翻页。
- **次级页面播放连续性**：为设置子页、听歌统计、全网检索与 QQ 音乐发现页挂载底部 `MiniPlayer` 并预留安全底部内边距。

### 🐛 4. Bug 修复与回归测试
- **修复多选初始状态与控制器释放风险**：修复「全部歌曲」进入批量管理时默认误选中首曲的问题；将歌单重命名与描述弹窗拆为独立状态组件并在 `State.dispose` 中释放输入控制器，消除关闭弹窗后的生命周期隐患。
- **多端与 Web 兼容加固**：补充 Web 壳层规范（`lang="zh-CN"`、`color-scheme`、`theme-color`）与多处 `!kIsWeb` 平台保护，M3U 导入兼容 `PlatformFile.readAsBytes()`；新增全 6 套配色对比度与 `320px + 2.0x` 缩放回归测试。

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

**Full Changelog**: https://github.com/e69d8e/AquaMoon/compare/v1.0.9...v1.0.10
