# EXIF / XMP / PNG 文本（只读）

在状态窗点击 **EXIF / XMP**。支持分组折叠、选中文字、单项复制和长文本展开。技术字段固定隐藏；不提供搜索、技术字段开关和复制全部工具栏。

## 格式范围

按文件签名识别，不依赖扩展名：

| 容器 | 支持内容 |
| --- | --- |
| JPEG | APP1 EXIF、标准 XMP、Extended XMP 分片重组 |
| PNG | eXIf、iTXt XMP，以及 tEXt / iTXt / zTXt 文本 |
| WebP | RIFF EXIF / XMP 块，支持奇数长度填充和可选 Exif 前缀 |
| 经典 TIFF | 首个主 IFD、EXIF/GPS/Interop 子 IFD、700 标签中的 XMP，支持大小端 |

PNG 文本显示为独立 **PNG 文本** 分组，不冒充 EXIF。支持 iTXt UTF-8、多语言标签、翻译后的关键字，以及压缩文本。AI 图片的 parameters / prompt / workflow 目前按原文显示，不解析为专用生成参数界面。文本可以位于 IDAT 之后。

- Windows XP* 按 UTF-16LE 解码，长文本和 UserComment 不按 120 字符过滤。
- XMP 保留字段路径、namespace URI、数组索引、多语言属性与嵌套属性。各来源不自动覆盖冲突值。
- Extended XMP 根据标准包的 HasExtendedXMP 引用关联 GUID，支持乱序分片；检查总长、偏移、空洞、重叠和 MD5。缺失、损坏或无引用分片给出警告，不把不完整内容当成功结果。
- TIFF 先将经过校验的元数据 IFD 重定位为紧凑 TIFF，再复用 exif 包解析。重定位后的结构指针不显示为原文件标签值。像素条带、瓦片、缩略图、MakerNotes 和填充数据不读取。
- TIFF 后续页、SubIFD 预览、BigTIFF 暂不支持；检测到时明确提示。HEIC/AVIF、其他 RAW、GIF 和 `.xmp` 旁车文件留待后续。
- 图片解码和 EXIF 自动方向逻辑保持原样。元数据失败不影响图片显示，不修改原文件。

## 性能与边界

`MetadataService` 不参与图片解码、尺寸探测和预取。只有状态窗可见且元数据展开时，停留 250 ms 后才发起读取。

- 文件扫描、解压和解析均在独立 isolate；主 isolate 只做异步 stat、缓存查询和展示。
- 按容器结构跳过像素块；TIFF 随机访问 IFD，不整文件读取、不读取固定长度的大文件头。
- 单服务最多一个活跃 worker；排队过期请求直接跳过。已运行 worker 不强杀，但旧结果不回写。
- 切图、收起、隐藏状态窗、dispose 使旧请求失效；generation 和路径再次校验。
- 16 项 LRU，键包含路径、大小、修改时间。
- 文件读取预算约 2 MB 元数据加 512 KB 结构开销，最多 20000 次读取。JPEG 最多 4096 个标记段。
- TIFF 输入/输出各限 2 MB，4096 个标签、32 个 IFD、8 层深度，校验范围和重复/循环引用。
- PNG 文本解压后总量限 2 MB，分块喂入解压器；压缩失败或超限后不再解压后续压缩块。只对读取的元数据块验证 CRC，不为 CRC 扫描像素块。
- Extended XMP 单包上限 2 MB；XMP 字段数、节点数与深度有限制。整个结果最多 4096 个字段。
- UI 按可见行懒构建，长文本默认折叠。限制触发时保留已经读到的可用数据并显示警告。

## 验证

```powershell
flutter analyze
flutter test
dart run tool/inspect_metadata.dart 'V:\壁纸\参考\Hannah5.jpg'
```

测试图仍能读出 `XPSubject=测试`、评论网址、Scott Eaton 作者/版权、Photoshop CC 2017 软件和 XMP 文档关系。未复制私人图片到仓库。

自动测试使用临时构造的容器，覆盖 PNG 压缩/多语言/CRC/解压限制、WebP 填充和边界、TIFF 大小端/远端 IFD/GPS/长评论/循环偏移、Extended XMP 乱序/超 64 KB/缺失/重复/MD5，以及界面技术字段隐藏/长文本/PNG 分组。16 MB 稀疏文件验证像素块跳过及远端 IFD 定位。

独立脚本耗时是后台元数据调用耗时，不是 release 翻图帧率或首帧性能基准；实际 UI 帧率需另行测量。
