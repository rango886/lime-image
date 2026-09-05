# lime image 开发文档

这个目录是给**后续接手的人（含 AI）**准备的上下文。根目录 `README.md` 面向使用者，
这里面向改代码的人。

## 阅读顺序

| 文档 | 内容 | 什么时候读 |
|---|---|---|
| [architecture.md](architecture.md) | 整体架构、模块职责、数据流、必须遵守的不变量 | **动任何代码前先读** |
| [decoding.md](decoding.md) | 多格式解码子系统：分层设计、WIC FFI、实测数据、踩坑记录 | 改解码 / 加格式支持 |
| [roadmap.md](roadmap.md) | 待办事项、已知限制、每项的成本与收益评估 | 决定下一步做什么 |

## 给 AI 的快速上手须知

1. **先跑探测工具再改解码相关代码**
   ```bash
   dart run tool/decoder_probe.dart <文件或目录> [--target=1024]
   ```
   `lib/services/decoders/` 刻意不依赖 `dart:ui` 和 Flutter，所以能用纯 `dart run` 直接跑。
   这是本项目最重要的调试杠杆——定位 WIC 的堆损坏 bug 全靠它，不用反复起 Flutter app。

2. **验证三连**
   ```bash
   dart analyze lib tool          # 必须 No issues（tool/ 的 avoid_print 是 info，可忽略）
   flutter test                   # 14 个解码回归测试
   flutter build windows --debug  # 确认真能编译
   ```

3. **本项目的性能预算是硬约束**。这是个看图器，按方向键翻页要在 100ms 内出图。
   任何改动如果让 `ViewerState.reload` 的关键路径变慢，就是 bug。
   详见 [architecture.md 的「性能不变量」](architecture.md#性能不变量必须遵守)。

4. **不要相信系统 API 的「声明」，只相信「真的跑成功过」**。
   这条是血的教训，见 [decoding.md 的踩坑记录](decoding.md#踩过的坑按重要性排序)。

5. **注释写中文**，跟现有代码保持一致。注释要解释**为什么**而不是**是什么**，
   尤其是那些"看起来多余但删了会出 bug"的地方。

## 项目基本信息

- Flutter SDK 约束：`^3.13.2`（`pubspec.yaml`）
- 目标平台：Windows / Linux / macOS 桌面（`web/` 目录存在但不是目标）
- 代码规模：`lib/` 约 9500 行 Dart
- 无状态管理框架，用 `ChangeNotifier` + `ValueNotifier`
- 无代码生成（没有 build_runner / freezed / json_serializable）
