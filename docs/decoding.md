# 多格式解码子系统

覆盖 `lib/services/decoders/`。这份文档记录**设计依据**和**踩过的坑**，
后者比前者更重要——里面有几个 bug 光看代码是想不出来的。

## 核心结论（都有实测支撑）

1. **WIC 白给最多**。Windows Imaging Component 已能解 TIFF / HEIC / HEIF / AVIF /
   JPEG XL / DDS + 35 种 RAW，零第三方依赖、零编译、跟系统「照片」应用能力一致。
2. **内嵌预览是降维打击**。PSD 缩略图 2ms vs ffmpeg 90ms vs 纯 Dart `image` 包 594ms。
   所以它是**第一优先级快路径**，不是优化项。
3. **进程 spawn 是 30ms 硬成本**，所以 CLI 只能兜底，且必须 stdout 直出 RGBA，
   绝不走 PNG 中转（24MP PNG 编码要 300~800ms）。
4. **不引入 `image` 包**。它能覆盖的格式 WIC + ffmpeg 全有，而且快 6~7 倍。
   注意 Dart AOT 比 JIT 更慢（594ms vs 452ms），Flutter release 对应的是 AOT 那个数。

## 分层

```
Layer 0  FormatSniffer          魔术字节嗅探，扩展名仅作辅助
Layer 1  Skia (现有路径)         png jpeg gif webp bmp ico apng
Layer 2  EmbeddedPreviewDecoder  PSD 资源1036 / RAW 内嵌 JPEG   priority 0
Layer 3  WicDecoder              tiff heic avif jxl dds + RAW   priority 10
Layer 4  FfmpegDecoder           psd tga exr hdr jp2 pcx qoi sgi priority 30
旁路      SvgRasterizer           svg svgz → flutter_svg，按 bucket 重新栅格化
```

Layer 2~4 全部在 **`DecodePool` 的常驻 worker isolate** 里执行（`decode_worker.dart`），
回传走 `TransferableTypedData`。主 isolate 只负责记账（黑名单 / 能力 / 统计）和
`ImageDescriptor` → GPU 上传。池子起不来时会退回主 isolate（`_decodeInline`），
宁可卡一下也要能看图，并把次数记在 `mainIsolateDecodes` 里暴露给设置页。

```

`DecoderRegistry` 按 priority 依次尝试，失败就降级并把 `(path, decoderId)` 记进黑名单，
避免同一文件反复付学费。

### 两种返回形态

`RawImageData` 刻意支持两种，这是设计上的关键取巧：

| 形态 | 场景 | 上层处理 |
|---|---|---|
| `encoded` | 从容器里抠出的 JPEG 预览 | 喂给 `ImageDescriptor.encoded`，**白拿 Skia 的降采样能力** |
| `frames` | WIC / ffmpeg 给的原始像素 | `ImageDescriptor.raw` + `instantiateCodec` |

`ImageService._decodeFromBuffer` 是从原 `_decode` 主体抽出来的，两条路径共用，
所以 bucket / LRU / pin / 动图帧预算逻辑一行没改。

### 内嵌预览的取舍规则

预览图往往很小（PSD 的 1036 资源通常 ~71×160），直接当主视图会糊。
`DecoderRegistry.decode` 里的判定：

```dart
if (r.previewOnly && r.effectiveWidth < targetWidth * 0.8) continue;  // 太糊，继续找
```

实测行为（1080×2404 的 PSD）：

| targetWidth | 选中的解码器 | 耗时 |
|---|---|---|
| 64 | embedded-preview | **4.4 ms** |
| 256 | ffmpeg | 154.7 ms |
| 1024 | ffmpeg | 191.2 ms |

于是缩略图栏/网格总览吃到 2~4ms 的快路径，主视图不会被糊图糊住。

## 纯 Dart，可脱离 Flutter 测试

`decoders/` 目录**不 import `dart:ui` 和 `package:flutter`**，代价是自己定义了
`RawPixelFormat`（而不是直接用 `ui.PixelFormat`），映射发生在 `ImageService`。

换来的收益极大（也是 isolate 化能很快做完的原因：worker 里直接 new 出整条解码链）：

```bash
dart run tool/decoder_probe.dart <文件或目录> [--target=1024]
# 验收 isolate 池：看尺寸/帧长度对不对、是否真的没回退到主 isolate
dart run tool/pool_check.dart <文件> [<文件> ...]
```

定位下面那个 WIC 堆损坏 bug 全靠这个工具，几秒一轮，不用起 Flutter app。
**新增解码器时请保持这个约束。**

## WIC FFI 实现要点

`package:win32` 6.x 精简了 COM 表面，**完全没有 WIC 接口**，所以 `wic_ffi.dart` 是手写的。
反而更好：连 `win32` 依赖都不需要，只用 `dart:ffi` + `package:ffi`。

### vtable 序号怎么算

```
绝对索引 = 3 (IUnknown 的 QueryInterface/AddRef/Release) + 继承链方法总数 + 局部偏移
```

**权威来源是 SDK 头文件，不要凭记忆**：

```powershell
$h='C:\Program Files (x86)\Windows Kits\10\Include\10.0.26100.0\um\wincodec.h'
# 提取接口方法顺序和 IID，见本文档末尾的提取脚本
```

已核对的表：

| 接口 | 继承 | 关键方法绝对索引 |
|---|---|---|
| `IWICImagingFactory` | IUnknown | CreateDecoderFromFilename **3**、CreateFormatConverter **10**、CreateBitmapScaler **11**、CreateComponentEnumerator **23** |
| `IWICBitmapDecoder` | IUnknown | GetFrameCount **12**、GetFrame **13** |
| `IWICBitmapSource` | IUnknown | GetSize **3**、GetPixelFormat **4**、GetResolution **5**、CopyPalette **6**、**CopyPixels 7** |
| `IWICBitmapFrameDecode` | IWICBitmapSource | GetMetadataQueryReader **8** |
| `IWICBitmapScaler` | IWICBitmapSource | Initialize **8** |
| `IWICFormatConverter` | IWICBitmapSource | Initialize **8**、CanConvert **9** |
| `IWICBitmapSourceTransform` | IUnknown | CopyPixels **3**、GetClosestSize **4**、GetClosestPixelFormat **5**、DoesSupportTransform **6** |
| `IWICMetadataQueryReader` | IUnknown | GetMetadataByName **5** |
| `IWICComponentInfo` | IUnknown | GetFriendlyName **10** |
| `IWICBitmapCodecInfo` | IWICComponentInfo | GetFileExtensions **17** |

### 像素格式

用 `GUID_WICPixelFormat32bppPBGRA` (`6FDDC324-4E03-4BFE-B185-3D77768DC910`)：
B,G,R,A + **预乘 alpha**，正好对上 Skia 的 `kPremul` + BGRA，零转换。

ffmpeg 那边给的是**直通 alpha**，所以 `FfmpegDecoder._premultiply` 必须做转换
（带"全不透明就跳过"的快速路径）。

### COM 初始化

`CoInitializeEx` 要在**每个 isolate 各做一次**。Dart 的顶层静态变量是 per-isolate 的，
正好用来记状态（`WicDecoder._comInited` / `_factory`）。
`DecodePool` 里每个 worker 因此各持一份 COM 状态 + 一个 `IWICImagingFactory`，
常驻不重复初始化 —— 这也是不用 `Isolate.run` 的原因（那样每张图都要重付
这笔开销）。worker 退出前会收到 `null` 消息，先 `dispose()` 释放 COM 对象。

### 能力枚举走 COM 而不是注册表

`WicDecoder.enumerateDecoders()` 用 `CreateComponentEnumerator` + `IWICBitmapDecoderInfo`，
能看到微软商店图像扩展装的 codec。本机实测枚举出 14 个（比读注册表还多认出
`DNG Decoder` 和 `WMPhoto Decoder`）。

## 踩过的坑（按重要性排序）

### 1. IID 记错导致堆损坏 ⚠️

我把 `IID_IWICBitmapSourceTransform` 写成了 `3B16811B-6A43-4EC9-A813-3D930C13B940`，
那实际是 **`IWICBitmapFrameDecode`** 的 IID。两者只差 4 个字节：

```
IWICBitmapFrameDecode      3B16811B-6A43-4EC9-A813-3D930C13B940
IWICBitmapSourceTransform  3B16811B-6A43-4EC9-B713-3D5A0C13B940   ← 正确
```

后果极其隐蔽：`QueryInterface` **成功**并返回 frame 自己，于是 vtable slot 4
从 `GetClosestSize(UINT*,UINT*)` 变成 `GetPixelFormat(GUID*)`，
往 4 字节的 out 参数里写了 16 字节 GUID → `0xC0000374` STATUS_HEAP_CORRUPTION，
而且崩溃点在后面很远的 `arena.releaseAll()`。

**诊断线索**：out 参数读回来是 `1876804388` = `0x6FDDC324`，正是所有 WIC 像素格式
GUID 的首个 dword。所有测试文件都返回同一个"垃圾值" → 说明是自己的绑定错了，
不是某个 codec 有问题。

### 2. `IWICBitmapSource` 有 5 个方法不是 4 个

漏了 `GetResolution`。导致 `CopyPixels` 和所有派生接口的方法全部偏移 1 位。

症状很误导：调 `Initialize` 却返回 `WINCODEC_ERR_NOTINITIALIZED (0x88982F0C)`
——因为实际打到了 `CopyPixels`，而未初始化的 scaler 对任何方法都报这个。
`FormatConverter.Initialize` 则一律 `E_INVALIDARG`。

**教训**：只要出现"调 A 方法却报了只可能来自 B 方法的错误"，
第一反应就该是 vtable 偏移错了，别去怀疑参数。

### 3. 注册表信息完全不可信

排查 JPEG XL 时发现：注册表 CLSID 项存在、`Patterns` 子键完整（裸码流 `FF 0A` 和
ISOBMFF 两种签名都注册了）、`InprocServer32` 指向的 `windowscodecs.dll` 也存在
——**但就是解不出来**。原因是那个 Store 扩展处于损坏状态，注册表项是残留空壳。
从商店重装后立刻正常。

**所以 `DecoderRegistry` 的能力判定只认「真的解成功过」**，
设置页把 `声称支持` 和 `已验证` 分开显示就是为了暴露这种静默故障。

顺带纠正一个错误推断：我曾以为微软的 JXL 解码器只吃 ISOBMFF 封装，
实测**裸码流 `FF 0A` 一样能解**。

### 4. ffmpeg 尺寸解析撞上 fourcc

ffmpeg 会打印 `Video: rawvideo (RGBA / 0x41424752), rgba, 512x1140`，
宽松的 `(\d+)x(\d+)` 正则会把 `0x41424752` 解析成 `0x414247` 当尺寸。
必须要求尺寸前面是**逗号 + 空白**：

```dart
RegExp(r',\s*(\d{1,6})x(\d{1,6})(?![\dxX])')
```

### 5. `scale=1024:-1` 会把小图放大

必须只缩不放。而且**不要用转义逗号的写法**：

```dart
'scale=min(iw\\,$W):-1'                        // ❌ 转义层数极易弄错
"scale=w='min(iw,$W)':h=-1:flags=lanczos"      // ✅ 命名参数 + 引号，无转义风险
```

我这里踩的具体坑是：经过工具链的 JSON 转义后源码里只剩单个反斜杠，
Dart 又把 `\,` 解析成 `,`，最终逗号没转义 → `Error parsing filterchain` →
报的错却是 `Error opening output file pipe:1`，完全指向错误方向。

### 6. WIC 的 shrink-on-load 没有想象中好

`IWICBitmapSourceTransform::GetClosestSize` 在本机对 **JPEG 也返回原尺寸**
（1500×1000 请求 1024 → 返回 1500×1000），即不提供 1/2、1/4、1/8 的 DCT 级降采样。
所以目前实际都走 `IWICBitmapScaler` + `IWICFormatConverter` 路径。

代码里保留了 transform 路径（有就用），但不要指望它带来加速。
早期用 WPF `TransformedBitmap` 测出"缩放零加速"与此一致。

### 7. 抽缩略图千万别开硬解

`-hwaccel d3d11va` 单帧场景下 **反而慢 3 倍**（366ms vs 121ms），
D3D11 设备初始化开销远大于解码收益。

### 8. `stdout.flush()` 会弄坏 sink

在 `tool/` 脚本里用 `stdout.writeln` + `stdout.flush()` 会抛
`Bad state: StreamSink is bound to a stream`。用 `print` 就好。

## 实测数据

测试机：Windows 11 25H2，ffmpeg full build（`V:\software\Tools\ffmpeg`）。

### 同源对照（1500×1000，同一张图四种编码）

| 格式 | 文件大小 | WIC 全分辨率解码 | 缩到 0.34x |
|---|---|---|---|
| JPEG | 562 KB | **9.5 ms** | 11.4 ms |
| PNG | 2816 KB | 25.3 ms | 26.9 ms |
| WebP | 296 KB | 36.7 ms | 34.0 ms |
| JPEG XL | 641 KB | **77.2 ms** | 79.2 ms |

JXL 比 JPEG 慢 8 倍，且无 shrink-on-load。24MP 线性外推约 1.2 秒
→ **必须靠缓存和预取掩盖**。

### PSD 解码路径对比（1080×2404，11.69 MB）

| 方案 | 耗时 |
|---|---|
| 内嵌缩略图（71×160） | **2.0 ms** |
| ffmpeg 纯解码（`-benchmark` rtime） | ~30 ms |
| ffmpeg 端到端（含 30ms spawn） | 89 ms |
| `image` 包 JIT | 452 ms |
| `image` 包 **AOT**（= Flutter release） | 594 ms |

缩放开销差距更大：ffmpeg `-vf scale` **+4.6ms**，`image` 的 `copyResize` **+65ms**。

### 各格式实际解码器与耗时（`--target=1024`）

| 格式 | 解码器 | 耗时 |
|---|---|---|
| TIFF | wic | 1.7 ms |
| JPEG XL (96×64) | wic | 1.3 ms |
| JPEG XL (1500×1000) | wic | 81.5 ms |
| AVIF | wic | 61 ms |
| PSD（缩略图档） | embedded-preview | 4.4 ms |
| PSD / TGA / EXR / HDR / JP2 / PCX / QOI / SGI | ffmpeg | 46–191 ms |

### 本机 WIC 解码器（COM 枚举结果）

```
BMP / GIF / ICO / CUR / JPEG / PNG / TIFF / DNG / WMPhoto / DDS Decoder
Microsoft HEIF Decoder        .heic .heif .hif .avci .heics .heifs .avcs .avif .avifs
Microsoft Webp Decoder        .webp
Microsoft Raw Image Decoder   36 个扩展名（.cr2 .cr3 .nef .arw .dng .raf .orf .rw2 .x3f …）
Microsoft JPEG XL Decoder     .jxl
```

依赖的 Store 扩展：`HEIFImageExtension` `HEVCVideoExtension` `AV1VideoExtension`
`RawImageExtension` `WebpImageExtension` `JPEG-XLImageExtension`。
缺哪个就少对应格式，设置页能看出来。

## 测试

```bash
flutter test test/decoders_test.dart     # 14 个用例
```

覆盖重点是**回归**而非覆盖率：

- JXL 双签名（裸码流 + ISOBMFF）—— 对应踩坑 3
- ISOBMFF brand 区分 HEIC / AVIF / CR3
- TIFF vs RAW 靠扩展名区分（魔术字节相同）
- 改错后缀时以内容为准
- PSD 资源 1036 解析（测试里手工构造最小 PSD）
- 内置格式不该进外部解码链
- Windows 上 WIC 可用且能枚举出 codec

样本文件在 `%TEMP%\limeimage_codec_probe\`（由 ffmpeg 生成的 16 种格式 +
`ref.jpg/png/webp` 同源对照组）。**这些是临时文件，会被系统清掉**，
需要长期回归的话得把样本纳入版本控制（见 roadmap 第 4 项）。

## 附：从 SDK 头文件提取 vtable 顺序

改 WIC 绑定前先跑这个，别凭记忆：

```powershell
$h = Get-ChildItem "C:\Program Files (x86)\Windows Kits\10\Include" -Recurse `
       -Filter 'wincodec.h' | Select-Object -First 1
$c = Get-Content $h.FullName -Raw

# 方法顺序
function Methods($iface){
  $m=[regex]::Match($c,"(?s)$iface\s*:\s*public\s+(\w+)\s*\{(.*?)\n\s*\};")
  Write-Output ("  : {0}" -f $m.Groups[1].Value)
  $i=0
  foreach($mm in [regex]::Matches($m.Groups[2].Value,'STDMETHODCALLTYPE\s+(\w+)\s*\(')){
    Write-Output ("    +{0}  {1}" -f $i,$mm.Groups[1].Value); $i++
  }
}
Methods 'IWICBitmapSourceTransform'

# IID
[regex]::Match($c, 'MIDL_INTERFACE\("([0-9a-fA-F\-]+)"\)\s*\r?\n\s*IWICBitmapSourceTransform\s*:')
```
