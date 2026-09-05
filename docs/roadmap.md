# 待办与已知限制

按建议优先级排列。每项都标了**为什么**和**大概多少工作量**，方便直接开工。

## 已完成（原第 1~3 项）

### ✅ 外部解码搬到 isolate

`lib/services/decoders/decode_worker.dart` 里的 `DecodePool`：常驻 worker isolate 池
（默认 `min(4, 核心数/2)`，设置里可调 0~8，0 = 自动）。

- 每个 worker 各持一份 COM 状态 + `IWICImagingFactory`（Dart 顶层静态天然
  per-isolate），所以**不用** `Isolate.run` —— 那样每张图都要重付初始化成本。
- 像素回传走 `TransferableTypedData`；`ui.Image` 仍在主 isolate 创建
  （`ImageDescriptor` / `instantiateCodec`，那步是 GPU 上传，很快）。
- ffmpeg 并发按 `ceil(3 / 池大小)` 分给每个 worker，总量仍约 3 个进程。
- 黑名单 / 能力验证 / 统计记账留在主 isolate（`DecoderRegistry`），worker 只解码，
  失败列表随响应回传给主 isolate 记账。
- 池起不来或 worker 崩了会退回主 isolate（`_decodeInline`），并计到
  `mainIsolateDecodes`，设置 → 解码器里红字提示（正常应为 0）。
- 顺手改进：太糊的内嵌预览现在会被留作兜底，真解码器全挂时用它顶上，
  而不是直接报错。
- 验收：`dart run tool/pool_check.dart <文件>`（本机 TIFF 走 WIC 11ms、
  TGA 走 ffmpeg 107ms、`mainIsolateDecodes=0`）+ `test/decoders_test.dart` 里的池测试。

### ✅ SVG 支持

`flutter_svg` 旁路，**没塞进位图管线**：`ImageService._decodeSvg` 按 bucket 重新栅格化
（`vg.loadPicture` → `PictureRecorder` → `toImage`）。

- `DecodedImage.vector = true`；`naturalWidth/Height` 用 SVG 逻辑尺寸（适应缩放靠它），
  `decodedWidth` 用实际栅格宽度，所以可以大于逻辑宽度。
- `viewer_state._maybeUpgradeQuality` 对矢量图跳过「不超过原尺寸」的限制，
  放大时会重新栅格得更清晰（上限 `maxDecodeDimension`）。
- `.svgz` / 被 gzip 过的 `.svg` 也能开。

### ✅ 扩展名表和运行时能力打通

- `kKnownImageExtensions`（列文件用）现在从 `kFormatExtensions`（`format_sniffer.dart`）
  推出来，加格式只需改嗅探器那张表；
  `decodableExtensions` / `isDecodableFile()` 由 `DecoderRegistry.initialize()`
  运行时填充（含 WIC 自己报的扩展名）。
- `folder_service` 默认继续用 known（解不了也列出来，保持浏览连续性）；
  新增 `settings.hideUndecodableFiles`，设置 → 文件 / 解码器两处都能开。
- 文件选择器过滤器改用 `kKnownImageExtensions`。

同时顺手做了：设置 → 解码器页重写（后端卡片 / isolate 池状态 / 格式按支持程度分组 +
tooltip / 本次运行统计）、关于页重写（标识 + 四个运行时数字 + 格式·用法·配置卡片），
以及 `tool/analysis_options.yaml`（关掉 `avoid_print`，`flutter analyze` 现在全绿）。

## 1. 动图 AVIF / HEIC 的帧间隔

**现状**：`WicDecoder` 多帧时帧间隔拿不到，固定填 100ms（见 `_decodeSync` 里的
`delays` 构造）。

**问题**：没有真实的动画 AVIF / 动画 HEIC 样本验证过。GIF 的延迟在 WIC 里可以通过
`/grctlext/Delay` 元数据查询拿到，但 AVIF/HEIF 容器的路径不一样，需要实测确定。

**做法**：先搞到样本文件，用 `tool/decoder_probe.dart` 看 `frameCount`，
再试各种 `IWICMetadataQueryReader` 查询路径。GIF/WebP 是 Skia 原生路径，不受影响。

**工作量**：小，但**卡在样本文件上**。

## 2. RAW 内嵌预览还没实际验证

**现状**：`EmbeddedPreviewDecoder._largestEmbeddedJpeg` 已实现（扫文件里最大的
JPEG 流，带正确的 SOS 段跳过逻辑，不是无脑搜 `FFD9`），但**没有真实 RAW 文件测过**。

**为什么值得做**：RAW 内嵌预览通常是**全尺寸**的，能把打开 RAW 的时间从秒级压到
几十毫秒，是各家看图器"打开 RAW 很快"的真正原因。目前 RAW 走 WIC 全解码。

**做法**：找一张 CR2/NEF/ARW 跑 `dart run tool/decoder_probe.dart <file> --target=2048`，
看 `embedded-preview` 是否被选中、尺寸是否够大。注意 CR3 是 ISOBMFF 容器，
预览在 box 里，当前的线性扫描可能拿不到。

**工作量**：小（验证）+ 中（如果 CR3 要单独处理 box 解析）。

## 3. HDR / EXR 浮点截断 与 ICC 色彩管理

**现状**：全部按 sRGB 8-bit 直出。

- HDR/EXR 是浮点，高光会被截断
- WIC 能给 ICC profile，但 Flutter 侧没有便捷的 CMS，广色域照片会偏艳

**做法**：等 Flutter 的 wide-gamut / `ui.ColorSpace` 支持成熟。
现在硬做的性价比很低。

**工作量**：大，且依赖上游。**建议先不动**。

## 4. 测试样本纳入版本控制

**问题**：`test/decoders_test.dart` 里的 PSD 是运行时手工构造的（很好），
但 `tool/decoder_probe.dart` 依赖 `%TEMP%\limeimage_codec_probe\`，
那是临时目录，会被系统清掉。

**做法**：建 `test/fixtures/`，放 16 种格式的最小样本（每个几百字节到几 KB）。
生成脚本（ffmpeg full build）：

```powershell
$src='-f lavfi -i testsrc=size=96x64:rate=1 -frames:v 1'
# png jpg webp gif bmp tiff tga jxl avif jp2 exr hdr qoi pcx sgi ico
# 具体命令见 git 历史 / decoding.md
```

再加一个矩阵测试：每格式 × 每解码器 → 断言尺寸正确 + 与对照组 PSNR 在阈值内。
这能防住**某次 Windows 更新悄悄改变 WIC 行为**。

**工作量**：小。

## 5. PSD 图层合成

**现状**：ffmpeg 只读**合成图（merged composite）**。关闭「最大化兼容性」保存的
PSD 里没有合成图，ffmpeg 会失败。

**做法**：这是唯一 `image` 包有独特价值的场景（它能自己合成图层）。
可以作为第四层兜底（priority 40），但要接受 ~600ms 的代价，且必须在 isolate 里跑。
建议**等有用户实际反馈再做**。

## 6. Linux / macOS 的系统解码器

**现状**：`DecoderRegistry` 里 `WicDecoder` 有 `Platform.isWindows` 守卫，
所以非 Windows 平台只有 embedded-preview + ffmpeg。

**做法**（让三平台对称、且都零编译零依赖）：

| 平台 | 系统解码器 | 备注 |
|---|---|---|
| Linux | **gdk-pixbuf**（FFI 直调） | Flutter Linux 本来就链 GTK3，所以**一定存在** |
| macOS | **Image I/O**（几十行 Swift/ObjC） | HEIC/RAW/TIFF/JXL/EXR，覆盖最全 |

gdk-pixbuf 的 `gdk_pixbuf_new_from_file_at_scale()` 自带按尺寸缩放解码，
和 bucket 机制天生匹配。装了 `heif-gdk-pixbuf` 就自动多出 HEIC/AVIF。

**工作量**：Linux 中等，macOS 中等（需要 platform channel 或 FFI）。

## 7. 视频（明确不做）

用户已决定先不支持。若将来要做，结论记录在这里以免重复讨论：

- **有 ffmpeg ≠ 能播视频**。1080p60 RGBA 管道要 **497 MB/s**，加上每帧
  `ui.Image` 创建 + GPU 上传，这条路不通。音频、A/V 同步、seek、硬解全要自己实现。
- 真要播放就用 **`media_kit`**（libmpv，内部也是 ffmpeg），渲染走 Flutter `Texture`，
  零拷贝、硬解、音频全包，代价是 bundle +40MB，且必须开独立的 `video_view.dart`，
  **绝对不能塞进 `ImageService`**（一个 8 秒 60fps 视频 = 480 帧 × 8.29MB = 4GB，
  会把 LRU 打爆）。
- **性价比最高的中间态**：视频当「可浏览条目」——抽首帧缩略图（实测 121ms，
  取 10% 处躲开黑场/淡入）+ ffprobe 元数据 + 磁盘缓存，双击交给系统播放器。
- **另一个很适合看图器的方向**：Live Photo / Motion Photo。手机动态照片是
  「JPEG/HEIC + 尾部内嵌 MP4」，检测并播放内嵌视频跟 PSD 抠预览是同一个套路，
  成本极低、体验惊艳。

## 从根 README 继承的其他待办

- **超大图分块（tile）渲染**：目前用降采样 + 渐进重解码，>16k 像素的图放到 1:1
  仍受纹理上限（`maxDecodeDimension` 默认 8192）限制。
- **无损旋转写回文件**：当前旋转/翻转只影响显示。
- **SVG 栅格的 bucket 颗粒度**：现在每个 bucket 各存一张位图，连续缩放会多栅格
  几次（每次几毫秒，影响不大）。真要优化就直接缓存 `ui.Picture` 按帧重画。
- **i18n**：现为中文硬编码。
- **更新检查**。
- **缩略图磁盘缓存**：`path_provider` 已是依赖，键用 `path + mtime + size`。
  和第 2 项（RAW 预览）配合收益最大。

## 清理项

- `lib/services/decoders/wic_decoder.dart` 里 `_formats` 包含 `jp2`，
  但本机 WIC 没有 JPEG 2000 codec，所以会有一次快速失败再降级到 ffmpeg。
  保留是为了可移植性（某些 OEM 装了 JP2 codec），成本约 1ms，可接受。
