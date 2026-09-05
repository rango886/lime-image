# lime image

极简、高性能的桌面图片查看器（Windows / macOS / Linux），Flutter 实现。

## 现在能跑起来了

```bash
cd limeimage
flutter run -d windows        # 或 -d macos / -d linux
flutter run -d windows -a "D:\pics\a.jpg"   # 带参数启动（等价于双击图片打开）
```

> **Windows 首次构建**：Flutter 编译带插件的项目需要符号链接权限，请先打开
> `设置 → 系统 → 开发者选项 → 开发人员模式`（或以管理员运行 `start ms-settings:developers`），
> 否则会报 *Building with plugins requires symlink support*。

## 多语言

支持简体中文、繁體中文、English、日本語、한국어。

* 无配置首次启动先显示语言选择页，确认并成功保存后才进入看图；通过命令行打开的图片会在选择完成后继续打开。
* 在 **设置 → 窗口与启动 → 语言** 中随时切换，无需重启。语言随其他设置保存在 `settings.json` 的 `language` 字段。
* 旧版本配置没有语言字段时保留简体中文；恢复默认设置保留当前语言。
* 翻译资源在 `lib/l10n/`，源表为 `tool/translations.tsv`（`|` 分隔，简体 / 英语 / 日语 / 韩语；繁体通过 OpenCC 生成）。修改后运行：

  ```sh
  uv run --with opencc-python-reimplemented tool/build_translations.py
  dart format lib/l10n/translations.dart
  flutter test test/localization_test.dart
  ```

  翻译已编译进程序，运行时不需要联网或 Python。文件名、路径、格式名和底层系统诊断保持原文。

## 目录结构

```
lib/
  main.dart                  启动：单实例、窗口位置恢复、命令行参数
  l10n/
    strings.dart             五种语言、配置标识、参数化翻译
    translations.dart        离线翻译资源（生成文件）
  core/
    utils.dart               格式表、自然排序、文件头尺寸探测（不解码拿宽高）
    platform_ops.dart        回收站、文件管理器定位、剪贴板、单实例 IPC、macOS 打开文件事件
  models/
    enums.dart               8 种查看方式 / 排序 / 滚轮动作 / 过渡 等枚举
    key_chord.dart           快捷键组合的解析 / 序列化 / 显示
    app_action.dart          全部可绑定动作 + 默认按键
    settings.dart            所有设置项 + 快捷键解析（全局 & 按查看方式覆盖）
  services/
    settings_service.dart    JSON 配置读写（防抖保存）+ 标记文件持久化
    image_service.dart       降采样解码、分级缓存(LRU/字节数)、预取、EXIF 方向、动图帧
    metadata_service.dart    按需后台元数据读取、缓存（详见 docs/metadata.md）
    metadata/                JPEG/PNG/WebP/TIFF 提取、EXIF/XMP、PNG 文本
    folder_service.dart      目录扫描、排序、文件监听、cbz/zip 解包
    decoders/                多格式解码器链（详见 docs/decoding.md）
      decoder.dart             RawDecoder 接口 + RawImageData
      format_sniffer.dart      22 种格式的魔术字节嗅探
      embedded_preview.dart    PSD 资源1036 / RAW 内嵌 JPEG 抽取（纯 Dart）
      wic_ffi.dart             Windows Imaging Component 的手写 COM 绑定
      wic_decoder.dart         WIC 解码 + 能力枚举
      ffmpeg_decoder.dart      外部 ffmpeg 兜底（rawvideo 管道）
      decoder_registry.dart    优先级链 / 降级 / 黑名单 / 能力记账
  state/
    viewer_state.dart        中枢：变换、模式、动图、导航、动作分发
  ui/
    app.dart / theme.dart    主题（亮/暗/强调色/棋盘格背景）
    language_page.dart       首次启动语言选择与保存失败重试
    viewer_page.dart         主界面、键盘、拖放、窗口事件、对话框
    image_canvas.dart        模式 1~6 的绘制与手势（滚轮/拖动/惯性/触控板/双击）
    comic_view.dart          模式 7 漫画连续滚动、模式 8 长图
    title_bar.dart           自绘自动隐藏标题栏 + 底部状态栏
    context_menu.dart        右键菜单（左侧功能名，右侧快捷键）
    panels.dart              缩略图栏、网格总览、HUD、快捷键帮助
    settings_page.dart       11 个分类的设置界面 + 快捷键录制器（含冲突检测）
packaging/
  linux/lime-image.desktop       Linux 文件关联
  windows/register-windows.ps1   Windows 默认程序注册（免管理员）
tool/
  decoder_probe.dart             解码器实测工具（纯 Dart，可脱离 Flutter 跑）
docs/
  architecture.md / decoding.md / roadmap.md
```

## 性能设计（"丝滑"的实现方式）

| 手段 | 位置 |
|---|---|
| 按视口尺寸**降采样解码**，绝不整分辨率进显存 | `ImageService._decode` + `targetDecodeWidth` |
| 分级缓存 bucket（256…8192），放大时后台重解码更清晰版本 | `ImageService.bucketFor` / `_maybeUpgradeQuality` |
| LRU 按**字节数**限制（默认 768MB），当前图 pin 住不回收 | `ImageService._trim` |
| 前后 N 张**预取**，切图零等待 | `ViewerState._prefetchNeighbors` |
| 平移/缩放只更新 `Matrix`，`RepaintBoundary` + 单次 `drawImageRect` | `ImagePainter` |
| 平移不触发整棵树重建（独立 `transformTick` 通道） | `ViewerState._bump` |
| 交互中降 `FilterQuality`，静止 160ms 后提质 | `markInteracting` / `_quality()` |
| 长按连切时旧解码结果按 generation 丢弃 | `ViewerState.reload` |
| 漫画模式先确定页面尺寸和位置，再按可见范围加载；缩放不改变页面布局 | `probeImageSize` / `_StripCanvas` / `StripTransform` |
| 超大图按 GPU 纹理上限（默认 8192px）自动限幅 | `maxDecodeDimension` |

## 界面说明

* 启动即为**无标题栏**状态，鼠标移到窗口顶部才滑出标题栏（只显示文件名 + 窗口三键），
  离开顶部后按「离开后多久隐藏」的延时收起（设置 → 外观）。
* 所有状态信息（序号/尺寸/缩放/大小/时间/动图帧/解码尺寸/缓存/标记/排序/常用快捷键）
  集中在**悬浮状态小窗**里，`H` 开关，位置可选四个角，透明度可调。
* 圆角半径、界面字体大小在 设置 → 外观 里统一控制（菜单、对话框、设置面板、状态窗都跟随）。
* 快捷键走**全局键盘钩子 + 物理按键回退匹配**，所以中文输入法开启时也能正常触发。

## 8 种查看方式的缩放规则

| 模式 | 缩放 | 位置 |
|---|---|---|
| 1 自动缩放 | 横图以窗口宽为基准、竖图以窗口高为基准（**小图也放大到填满**）；基准边会让另一边溢出时退到「完整显示」，**不裁切** | 居中 |
| 2 焦点缩放锁定 | 记住缩放率 | 记住「视口中心对应的图片位置」（归一化），换图 / 改窗口大小 / 进出全屏都还原同一处画面 |
| 3 宽度优先 | 宽度**真正填满**窗口（含放大小图） | 顶部对齐，上下拖动看 |
| 4 高度优先 | 高度**真正填满**窗口（含放大小图） | 左对齐（日漫方向为右对齐） |
| 5 中心缩放锁定 | 记住缩放率 | 始终图片中心对齐视口中心 |
| 6 双页模式 | 两张拼成一张后完整显示 | 居中；←/→ 翻两页，Shift+←/→ 翻一页 |
| 7 漫画模式 | 进入时第一页占满宽度；Ctrl+滚轮围绕鼠标精准缩放 | 整个目录作为虚拟长图，自由平移，无居中、边界回弹和缩放倍率限制 |
| 8 长图模式 | 进入时图片占满宽度；Ctrl+滚轮围绕鼠标精准缩放 | 同漫画画布，滚轮上下平移、拖动自由移动，允许移出窗口 |

漫画 / 长图的布局在缩放时保持固定，缩小到窗口以内也不会自动居中。滚轮放大与缩小使用互为倒数的倍率；“适应窗口”或重置才重新以当前窗口宽度铺满、回到顶部。窗口大小变化本身不会改变画布锚点。漫画首次进入会先读取目录内页面尺寸（无法探测的格式会尝试解码），之后只加载可见及预加载范围内的页面；不生成巨型拼接位图。

「不放大小图」设置只影响 2/5/6（锁定 / 双页）；1/3/4/7/8 是「填满」语义，小图也一定填满窗口。
常显标题栏（关掉自动隐藏）时，画面区域会让出标题栏那一条，避免图片顶部被盖住。

## 快捷键（默认，全部可改）

| | |
|---|---|
| ←/→、滚轮 | 上一张 / 下一张（可按住连切） |
| Ctrl+滚轮 | 以鼠标位置为中心缩放 |
| 左键拖动 | 平移（带惯性） |
| 1~8 | 自动 / 宽度 / 高度 / 焦点锁定 / 中心锁定 / 双页 / 漫画 / 长图 |
| Shift+←/→ | 双页模式下单页翻页 |
| ↑/↓、PgUp/PgDn | 滚动（漫画 / 长图模式） |
| + / - / 0 / Shift+0 | 放大 / 缩小 / 100% / 适应窗口 |
| Home / End | 第一张 / 最后一张 |
| n / Shift+n、t / Shift+t、s / Shift+s | 名称、时间、大小 正序/逆序 |
| r / Shift+r、m / Shift+m | 旋转、翻转 |
| l | 打开所在文件夹 |
| x / Shift+x | 标记 / 只看标记项 |
| Space、,、. | 动图 暂停播放 / 上一帧 / 下一帧 |
| b / g / p / h | 缩略图栏 / 网格总览 / 幻灯片 / **状态悬浮窗**（内含 EXIF / XMP / PNG 文本展开） |
| F11 / Esc / Ctrl+M | 全屏 / 关闭（先退出叠层）/ 最大化 |
| Ctrl+O、Ctrl+C、Ctrl+Shift+C、Ctrl+V、F2、Delete | 打开、复制图片、复制路径、粘贴打开、重命名、删除到回收站 |
| Ctrl+, / F1 | 设置 / 快捷键帮助 |

每种查看方式都可以单独覆盖键盘和滚轮绑定：设置 → 快捷键 → "作用范围" 选具体模式；设置 → 鼠标 里按模式分别配置滚轮/Ctrl 滚轮/Shift 滚轮/Alt 滚轮/拖动键。

## 平台集成

* **Windows / Linux**：命令行第一个参数即打开的文件（`main(List<String> args)`）。
* **macOS**：Finder 双击 / 拖到 Dock 走 Apple Event，已在 `macos/Runner/AppDelegate.swift`
  里实现 `application(_:open:)` → MethodChannel `limeimage/platform`，并在 `Info.plist`
  声明 `CFBundleDocumentTypes`；沙盒已关闭（默认看图程序需要任意路径访问）。
* **单实例**：设置里可选「复用已有窗口」或「每次新窗口」。复用模式用 127.0.0.1:47823
  做互斥与参数传递。
* **文件关联**：Windows 用 `packaging/windows/register-windows.ps1`；
  Linux 装 `packaging/linux/lime-image.desktop` 后 `xdg-mime default limeimage.desktop image/png …`。

## 格式支持

| 层 | 格式 | 依赖 |
|---|---|---|
| Skia 内置 | PNG / JPEG / GIF / WebP / BMP / ICO / APNG（含动图） | 无 |
| **WIC**（Windows） | TIFF / HEIC / HEIF / AVIF / **JPEG XL** / DDS + 35 种 RAW（CR2 CR3 NEF ARW DNG RAF ORF RW2 X3F…） | 无，用系统解码器 |
| **内嵌预览** | PSD 缩略图、RAW 内嵌 JPEG | 无，纯 Dart |
| **ffmpeg**（可选） | PSD / TGA / EXR / HDR / JP2 / PCX / QOI / SGI | 装了才启用，自动探测 |
| 未支持 | SVG | 待接 `flutter_svg` |

解码器链在 `lib/services/decoders/`，按 `优先级` 依次尝试并自动降级。
在 **设置 → 解码器** 里可以看到本机每种格式的真实支持状态、WIC 解码器清单，
以及手动指定 ffmpeg 路径。

命令行实测工具：

```bash
dart run tool/decoder_probe.dart <文件或目录> [--target=1024]
```

## 支持的图片格式（纯文本）

PNG, JPEG, GIF, WebP, BMP, ICO, APNG, TIFF, HEIC, HEIF, AVIF, JPEG XL, DDS, RAW, CR2, CR3, NEF, ARW, DNG, RAF, ORF, RW2, X3F, PSD, TGA, EXR, HDR, JP2, PCX, QOI, SGI

## 发布（GitHub Actions）

打 `v*` 标签即在 GitHub Actions 上并行构建 Windows / macOS / Linux 三平台包并创建 draft Release：

```bash
git tag v1.0.0 && git push origin v1.0.0
```

工作流在 `.github/workflows/`（`ci.yml` 质量门禁、`release.yml` 发版）。
产物构成、Windows 包里 `setup.bat` 的目录约束、glibc 兼容、签名等细节见
[docs/release.md](release.md)。

## 开发文档

改代码前请先读 [`docs/`](docs/)：

- [docs/architecture.md](docs/architecture.md) — 整体架构、数据流、**性能不变量**
- [docs/decoding.md](docs/decoding.md) — 解码子系统设计、WIC FFI、实测数据、踩坑记录
- [docs/release.md](docs/release.md) — GitHub Actions 打包发布流程与注意事项
- [docs/roadmap.md](docs/roadmap.md) — 待办与已知限制
