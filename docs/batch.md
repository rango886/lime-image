# 批量转换

独立窗口，用来把一批图片统一裁切 / 旋转 / 缩放 / 转格式。和看图窗口是两个进程，互不影响。

## 入口

| 入口 | 命令行 |
|---|---|
| 右键图片（可多选） | `lime-image.exe --batch "<文件>"` |
| 右键文件夹 | `lime-image.exe --batch "<文件夹>"` |
| 文件夹空白处右键 | `lime-image.exe --batch "<当前文件夹>"`（注册表里是 `%V`） |
| 手动 | `lime-image.exe --batch <文件或文件夹>...` |

Explorer 多选时会**给每个文件各起一个进程**。第一个进程占住端口 `47824`（`kBatchPort`，
和看图窗口的单实例端口分开），开窗口；后面的进程把路径发给它然后直接退出。所以不管选多少个，
最后都只有一个窗口。

右键盘符根目录空白处时，命令行是 `"C:\"`，Windows 的参数解析会把 `\"` 当成转义引号，
进程拿到的是 `C:"`。`BatchState.addPaths` 里专门把它还原成 `C:\`。

### 右键菜单注册

由 `packaging/windows/assoc/register-limeimage.ps1` 负责，全部写在 `HKCU`，不需要管理员：

| 位置 | 注册表键 |
|---|---|
| 图片 | `HKCU\Software\Classes\SystemFileAssociations\<.ext>\shell\LimeImage.Batch` |
| 文件夹 | `HKCU\Software\Classes\Directory\shell\LimeImage.Batch` |
| 文件夹空白处 | `HKCU\Software\Classes\Directory\Background\shell\LimeImage.Batch` |

- 挂在 `SystemFileAssociations` 下，所以**不管默认看图程序是谁**菜单都在，也不会动文件关联。
- `MultiSelectModel=Player`：默认值下选中超过 15 个文件菜单会消失，`Player` 不限数量。
- `.cbz` 不加（压缩包不是单张图）。
- 菜单文字：先读 exe 同目录 `settings.json` 的 `language`，没有再看系统显示语言；也可以 `-MenuText` 指定。
- Win11 的新右键菜单不显示经典 shell 动词，要在“显示更多选项”（Shift+F10）里找。

```powershell
register-limeimage.ps1                    # 文件关联 + 右键菜单
register-limeimage.ps1 -NoContextMenu     # 只要文件关联
register-limeimage.ps1 -ContextMenuOnly   # 只加右键菜单
register-limeimage.ps1 -RemoveContextMenu # 只删右键菜单
register-limeimage.ps1 -Unregister        # 全部撤销（含右键菜单）
```

删除时是**扫描注册表**删掉所有 `LimeImage.Batch`，扩展名列表改过也能删干净；删除不需要 exe 还在。
`setup.bat` 的菜单里对应 3 / 4 两项。

## 代码结构

```
lib/batch/
  batch_main.dart        --batch 入口：单实例、开窗口
  batch_state.dart       文件列表、预设、预览、执行（ChangeNotifier）
  convert_preset.dart    一组参数 + 各种枚举；JSON 存盘
  preset_store.dart      presets/*.json 和 batch.json
  naming.dart            文件名模板、输出目录、重名处理
  engine/
    convert_engine.dart  单张图的完整流水线（纯 Dart，不依赖 dart:ui）
    convert_pool.dart    常驻 isolate 池，排队、可取消
    wic_codec.dart       JPEG/PNG/TIFF/BMP 编码（Windows WIC）
    ffmpeg_codec.dart    WebP/AVIF 编码（以及非 Windows 的兜底）
    exif_patch.dart      EXIF 回写：方向归 1、去 GPS
    pixels.dart          RGBA 像素操作：摆正、裁切、缩放、铺底色
lib/ui/batch/            三栏界面
```

### 窗口布局和文件夹扫描

- 窗口默认 1440×900，左栏默认宽 320，可拖动与预览之间的分隔线调整宽度，双击恢复默认。
  中间预览至少保留 480 的宽度；窗口宽度小于 1200 时，文件列表通过标题栏按钮展开，不挤占中间区域。
- 属性对比和双行完整路径统一固定在中间预览下方，左栏只保留文件列表；窗口底栏只显示进度和操作按钮。
- 属性对比使用独立圆角卡片，转换后行轻微高亮，体积变化以徽标显示；较宽时横排三行，窄窗口改为纵向对比。
- 两行路径分别带原图/输出图标和标签，完整路径独立横向滚动，右侧可一键复制；不重复显示单独的文件名。
- “包含子文件夹”仍在文件列表的“…”菜单内，切换后立即更新已加入文件夹的列表，不用重新添加。
  关闭时只移除递归带入的图片，单独添加的文件和单独加入的子文件夹直属图片保留。
  开启后仍跳过预设的输出子文件夹，避免把转换结果再次加入；清空列表也会清除记住的文件夹。

### 一张图的流水线

解码 → EXIF 摆正 → 裁切 → 旋转/翻转 → 缩放 → 编码 → 写元数据 → 写文件

各项启用的处理按这个固定顺序叠加，**不取决于点选顺序**。同时启用裁切和尺寸时，先裁切，再对裁切结果缩放。
例如 200×100 的原图，裁成 100×40、顺时针转 90°、再指定宽 20，最终结果是 20×50。
“方向”组中的手动旋转/翻转发生在裁切之后；界面不额外显示处理顺序提示。

- 裁切框坐标是**摆正之后**的归一化坐标（0~1），单张手动拖的框存在 `cropOverrides`，只对那张生效。
- 体积上限：有损格式二分质量；“避免变大”时结果比原图大就直接复制原图（`keepOriginal`）。
- 写文件先写 `<目标>.limetmp` 再 rename，中途失败不会留下半个文件。
- 取消：排队中的任务直接以“已取消”结束；已经在算的结果回来后也丢掉，保持“未处理”状态。

### 翻译

worker isolate 里没有界面语言，所以引擎返回的错误 / 跳过原因是**中文原文**，
界面显示时再 `lt()`。新加这类字符串要同时进 `tool/translations.tsv`。

检查漏翻：

```bash
uv run --no-project tool/scan_untranslated.py lib
uv run --no-project --with opencc-python-reimplemented tool/build_translations.py
dart format lib/l10n/translations.dart
```

TSV 可选第 5 列手写繁中（比如台湾用语“資料夾”），留空就用 OpenCC 自动转。

## 测试

- `test/batch_engine_test.dart`：引擎层，各格式编码回读、EXIF、命名、体积上限
- `test/batch_state_test.dart`：状态层，加文件夹/去重/根目录路径修正、完整跑一遍和汇总、
  重名跳过、取消、预设另存/重命名/只改大小写/删除/导入导出

这两个测试文件需要 PATH 里有 ffmpeg 来造测试图，没有会跳过。

- `test/batch_file_scan_test.dart`：无需 ffmpeg，检查递归开关即时刷新、空根目录、去重、显式添加和快速切换。
- `test/batch_layout_test.dart`：检查中间预览下方的信息和路径、左栏宽度和拖动、预览最小宽度、窄窗口布局。
- `test/batch_info_style_test.dart`：检查明暗主题、不同宽度下的信息卡片、体积徽标和路径复制。
  Windows 上可用 `flutter test --dart-define=UPDATE_BATCH_SCREENSHOTS=true test/batch_info_style_test.dart`
  生成使用系统字体的 `build/batch-info-dark.png` / `build/batch-info-light.png` 样式截图。
