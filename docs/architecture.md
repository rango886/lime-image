# 架构

## 一句话概括

单窗口桌面看图器。`ViewerState` 是唯一中枢（`ChangeNotifier`），
三个 Service 分别负责**解码缓存**、**目录扫描**、**配置持久化**，
UI 层全部从 `ViewerState` 取数据、通过 `AppAction` 回写。

## 分层

```
main.dart
  │  单实例 IPC / 窗口位置恢复 / 命令行参数
  ▼
ViewerState  ◄──────────────────────────┐  中枢：变换矩阵、模式、动图、导航、动作分发
  │                                     │
  ├── ImageService     解码 + 分级缓存 + 预取
  │     └── DecoderRegistry  外部解码器链（见 decoding.md）
  ├── FolderService    目录扫描 / 排序 / 监听 / cbz 解包
  ├── SettingsService  JSON 配置读写（防抖）
  └── MarksService     标记持久化
                                        │
UI (viewer_page / image_canvas / ...) ──┘  只读 state，通过 invoke(AppAction) 回写
```

### 为什么没有状态管理框架

窗口只有一个、状态树很浅、更新频率极高（平移时每帧）。用 Provider/Riverpod 反而会
在平移路径上引入不必要的重建。当前方案是**双通道通知**：

- `notifyListeners()` — 结构性变化（换图、换模式、开关面板）
- `transformTick` (`ValueNotifier<int>`) — 只影响绘制的变化（平移/缩放）

平移时只 `_bump()` 递增 `transformTick`，只有监听它的 `ImagePainter` 重绘，
整棵 widget 树不动。**改动时千万别把平移改成走 `notifyListeners()`**。

## 模块职责

### `lib/core/`

| 文件 | 职责 | 注意 |
|---|---|---|
| `utils.dart` | 扩展名表、自然排序、**不解码读文件头拿宽高**(`probeImageSize`) | `probeImageSize` 是漫画模式滚动区间预算的基础，不能变慢 |
| `platform_ops.dart` | 回收站、文件管理器定位、剪贴板、单实例 IPC、macOS Apple Event | 平台差异都收敛在这里 |

`utils.dart` 里的扩展名表：

- `kNativeExtensions` — Skia 直解，走原路径
- `kExtraExtensions` — 需要外部解码器的常见格式（给人看的速览）
- `kKnownImageExtensions` — **列文件用**，从 `kFormatExtensions`（`format_sniffer.dart`）
  推出来的全集，含全部 RAW 扩展名。加一种格式只需改嗅探器那张表。
- `decodableExtensions` / `isDecodableFile()` — **实际解码用**，由
  `DecoderRegistry.initialize()` 在探测完后端后运行时填充
  （`setDecodableExtensions`）。只有 `settings.hideUndecodableFiles` 打开时
  才用它过滤文件列表 —— 默认不过滤，少列文件比点开报错更让人困惑。
- `kArchiveExtensions` — `.zip` / `.cbz`

### `lib/models/`

纯数据 + 枚举，无逻辑依赖，可安全单独修改。

- `enums.dart` — 13 个枚举。核心是 `ViewMode` 的 8 种查看方式：
  `autoFit` `fitWidth` `fitHeight` `focusLock` `centerLock` `doublePage` `comic` `longStrip`
- `app_action.dart` — 所有可绑定动作 + 默认按键。**加功能时先在这里加 action**，
  这样快捷键、右键菜单、设置页会自动带上。
- `key_chord.dart` — 快捷键组合的解析/序列化/显示
- `settings.dart` — 所有设置项（约 90 个）+ 快捷键解析（全局 & 按模式覆盖）
  - 加设置项要改三处：字段声明、`toJson()`、`fromJson()`。漏掉任何一处都不会报错，
    只会静默丢配置。

### `lib/services/`

#### `ImageService` — 最性能敏感的地方

```
load(path, targetWidth)
  → bucketFor(targetWidth)          吸附到 [256,512,1024,1536,2048,3072,4096,6144,8192]
  → 命中 _cache? 返回
  → 命中 _inflight? 复用同一个 Future（防重复解码）
  → _decode(path, bucket)
      ├─ FormatSniffer 嗅探格式
      ├─ 原生格式 → _decodeNative   → _decodeFromBuffer  (Skia)
      └─ 其他     → _decodeExternal → DecoderRegistry    (WIC / ffmpeg / 内嵌预览)
  → _insert(key, img)               新解码的先 pin=1 保护
  → _trim()                         按字节数 LRU（默认 768MB）
```

几个容易踩的点：

- **缓存 key 是 `path|bucket`**，同一张图会有多个分辨率版本共存。
  `cached(path, minWidth:)` 用来实现「先显示低清版本、高清解完自动升级」。
- **`_insert` 里 `entry.pins = 1` 不是多余的**。不加的话大图会在同一轮 `_trim()` 里
  被立刻 dispose，调用方拿到已销毁的 `DecodedImage`，表现是"有时候不显示图片"。
- `pin(path)` 只保护当前图，其他置 0。不这么做 pin 会越积越多导致缓存无法回收。
- 动图整体像素预算 256MB，超了截断并置 `truncatedFrames`。

#### `FolderService`

目录扫描 → 排序 → `watcher` 监听（防抖）→ `entries` + `index`。
`.cbz`/`.zip` 解到 `systemTemp/limeimage_<hash>` 后当普通目录处理。

#### `SettingsService`

JSON 防抖写盘。支持独立设置窗口进程改完后**热加载**（`ViewerState.onSettingsChanged`）。

### `lib/state/viewer_state.dart` (1170 行，最大的文件)

按注释分区：生命周期 / 加载 / 变换与适配 / 模式切换 / 动图 / 导航 / HUD /
幻灯片 / 文件操作 / 窗口 / 动作分发。

关键字段：

```dart
double scale; Offset offset; int quarter; bool flipH, flipV;   // 变换
ViewMode mode; Size viewport; double devicePixelRatio;
DecodedImage? image; DecodedImage? secondImage;                 // 双页模式用两张
int _generation;                                               // 丢弃过期解码结果
ValueNotifier<int> transformTick;                              // 绘制通道
```

`targetDecodeWidth` 决定解码分辨率，是性能与清晰度的平衡点：

```dart
final vw = math.max(viewport.width, 640) * devicePixelRatio;
return (vw * 1.25).round().clamp(256, settings.maxDecodeDimension);
```

`1.25` 是留给小幅放大的余量；`maxDecodeDimension` 默认 8192 对应 GPU 纹理上限。

### `lib/ui/`

| 文件 | 负责 |
|---|---|
| `viewer_page.dart` | 主界面、键盘、拖放、窗口事件、对话框、错误框 |
| `image_canvas.dart` | 模式 1~6 的绘制与手势（滚轮/拖动/惯性/触控板/双击） |
| `comic_view.dart` | 模式 7 漫画连续滚动、模式 8 长图 |
| `title_bar.dart` | 自绘自动隐藏标题栏 + 底部状态栏 |
| `panels.dart` | 缩略图栏、网格总览、HUD、快捷键帮助 |
| `settings_page.dart` | 11 个分类的设置界面 + 快捷键录制器（含冲突检测） |
| `context_menu.dart` | 右键菜单 |
| `theme.dart` / `widgets.dart` | 主题、通用控件 |

## 数据流

### 换图（最热路径）

```
用户按 →
  ViewerState.invoke(AppAction.next)
  → navigate(+1)  → folder.index++
  → reload()
      _generation++                          旧解码结果作废
      images.load(path, targetDecodeWidth)    命中缓存则同步返回
      images.pin(path)
      applyFitForMode()                      算 scale/offset
      notifyListeners()
      _prefetchNeighbors()                   后台预取前后 N 张
      _loadExif()                            状态窗 EXIF 用
```

### 平移（不重建树）

```
拖动 → panBy(delta) → clampOffset() → _bump() → transformTick++
     → 只有 ImagePainter 重绘
```

### 放大后提质

```
zoomAt() → markInteracting()（降 FilterQuality）
        → 静止 highQualityDelayMs(160ms) 后
        → _maybeUpgradeQuality() → images.load(更大 bucket) → 替换 image
```

## 性能不变量（必须遵守）

违反其中任何一条都会让"丝滑"感消失，且很难在 code review 里发现：

1. **绝不整分辨率解码**。一切走 `bucketFor` + `targetDecodeWidth`。
2. **平移/缩放不走 `notifyListeners()`**，只递增 `transformTick`。
3. **绘制路径保持单次 `drawImageRect`**，外面包 `RepaintBoundary`。
4. **交互中降 `FilterQuality`**，静止后再提质。
5. **换图后旧的异步解码结果必须按 `_generation` 丢弃**，否则长按连切会闪回旧图。
6. **漫画模式的行高用 `probeImageSize`（只读文件头）预算**，不能为了拿尺寸去解码。
7. **新解码结果先 pin 住再放进 LRU**。
8. **解码不能阻塞 UI 线程超过一帧**。外部解码（WIC / ffmpeg / 内嵌预览）跑在
   `DecodePool` 的常驻 worker isolate 里，主 isolate 只做 `ImageDescriptor` /
   `instantiateCodec`（GPU 上传）。`registry.mainIsolateDecodes > 0` 说明降级到
   主 isolate 了（池起不来才会发生），设置 → 解码器 里会红字提示。
9. **SVG 不进位图管线**。按 bucket 重新栅格化（`ImageService._decodeSvg`），
   `DecodedImage.vector = true`，放大时允许超过 `naturalWidth` 再栅格一次。

## 平台集成

- **Windows / Linux**：命令行第一个参数即打开的文件
- **macOS**：Finder 双击走 Apple Event → `AppDelegate.swift` → MethodChannel `limeimage/platform`
- **单实例**：`127.0.0.1:47823` 做互斥与参数传递，设置里可切「复用窗口 / 每次新窗口」
- **文件关联**：`packaging/windows/register-windows.ps1`、`packaging/linux/lime-image.desktop`

## 修改指南

| 想做什么 | 改哪里 |
|---|---|
| 加一个可绑定的功能 | `app_action.dart` 加 action → `ViewerState.invoke` 加分支 |
| 加设置项 | `settings.dart` 三处（字段 / `toJson` / `fromJson`）+ `settings_page.dart` |
| 加图片格式 | `decoders/` 加一个 `RawDecoder`，注册进 `DecoderRegistry`。详见 decoding.md |
| 加查看模式 | `enums.dart` 的 `ViewMode` + `image_canvas.dart` 或新建 view + `fitScale` |
| 改主题 | `theme.dart` |
