# 发布与打包（GitHub Actions）

Windows / macOS / Linux 三平台的构建、打包、发版全部在 GitHub Actions 上完成，
本地不需要装齐三套工具链。工作流文件在 `.github/workflows/`。

| 文件 | 触发 | 做什么 |
|---|---|---|
| `ci.yml` | push 到 main/master、PR、手动 | `dart format` 检查 + `flutter analyze` + `flutter test`，再在三平台各做一次 release 构建冒烟 |
| `release.yml` | push `v*` 标签、手动 | 三平台并行构建打包，上传 artifacts；标签触发时额外创建 **draft** Release |

## 发一个版本

```bash
git tag v1.0.0
git push origin v1.0.0
```

约 10~20 分钟后到仓库 **Releases** 页，会看到一个草稿，里面挂着三个平台的包。
检查无误后点 Publish。

想先验证流水线而不发版：Actions → Release → **Run workflow**，填个版本号（如 `1.0.0-rc1`）。
手动触发只上传 artifacts（保留 90 天），不会创建 Release。

## 产物

| 平台 | 文件名 | 运行环境 | 内容 |
|---|---|---|---|
| Windows | `lime-image-<ver>-windows-x64.zip` | Windows 10/11 x64 | `build/windows/x64/runner/Release/` 全量 + `setup.bat` + `assoc/` + README |
| macOS | `lime-image-<ver>-macos.dmg`（另有 `.zip`） | macOS 12+ / Apple Silicon | `lime-image.app` + `/Applications` 软链 |
| Linux | `lime-image-<ver>-linux-x64.tar.gz` | glibc ≥ 2.35（Ubuntu 22.04+） | `bundle/` 全量 + `lime-image.desktop` + `install.sh` |

三个包都是**绿色版**，解压即用，不写注册表 / 不装系统目录（除非用户主动跑安装脚本）。

### Windows 包的目录布局（重要）

```
lime-image-1.0.0-windows-x64/
  lime-image.exe
  flutter_windows.dll
  data/ ...
  setup.bat                    ← 与 exe 同级
  assoc/
    register-limeimage.ps1
    set-default-limeimage.ps1
    SFTA.ps1
```

这个层级不能动。`packaging/windows/setup.bat` 里写死了：

* `cd /d "%~dp0"`，然后找 `%~dp0assoc\register-limeimage.ps1`；
* `register-limeimage.ps1` 在**自身目录**和**上一级目录**两处找 `lime-image.exe`。

所以 `setup.bat` 必须和 exe 平级、`assoc/` 必须在 `setup.bat` 旁边。
workflow 的组装步骤里加了 `Test-Path` 断言（缺 exe 或缺 setup.bat 直接让构建失败），
避免路径摆错却照样发出去，用户双击没反应。

改动 `packaging/windows/` 下的文件名或相对路径时，**同步改 `release.yml` 的组装步骤**。

### Linux 的 install.sh

这个脚本不在仓库里，是 workflow 打包时生成的（内容见 `release.yml`）。它做四件事：

1. 拷贝整个 bundle 到 `~/.local/share/lime-image`；
2. 在 `~/.local/bin/lime-image` 建软链；
3. 把 `lime-image.desktop` 的 `Exec=` 改写成实际绝对路径后装进 `~/.local/share/applications/`
   （仓库里那份的 `Exec=lime-image` 只是占位，注释里也写了要改）；
4. 对 README 列出的图片 MIME 类型逐个 `xdg-mime default`。

全程不需要 root。要改关联的格式列表，同时改 `packaging/linux/lime-image.desktop` 的 `MimeType=`
和 `release.yml` 里那个 `for m in ...` 循环。

## 版本号从哪来

标签 `v1.0.0` → 去掉 `v` → 通过 `--build-name=1.0.0` 传给 `flutter build`，
`--build-number` 用 `github.run_number`。

**`pubspec.yaml` 里的 `version:` 不用手改**，命令行参数会覆盖它。这样不会出现
「tag 是 v1.2.0，包里显示 1.0.0」这种对不上的情况。

## 注意事项

### 1. Flutter 版本默认不锁

`release.yml` 顶部：

```yaml
FLUTTER_CHANNEL: stable
FLUTTER_VERSION: ''      # 留空 = channel 最新
```

本项目有手写的 WIC COM FFI（`lib/services/decoders/wic_ffi.dart`）和一批桌面端插件，
对 Flutter / Dart SDK 升级是敏感的。**正式发版前建议把 `FLUTTER_VERSION` 填成具体版本号**
（例如 `3.35.5`），否则哪天 stable 一动，构建挂了还得先排查是不是自己代码的问题。
`ci.yml` 可以继续跟 stable 最新，用来提前发现上游破坏性变更。

### 2. Linux 必须钉在 ubuntu-22.04

Flutter 的 Linux 产物动态链接 glibc，**在高版本系统上构建的包，低版本系统跑不起来**
（`GLIBC_2.38 not found`）。所以用 `ubuntu-22.04` 而不是 `ubuntu-latest`，
换来 glibc 2.35 的兼容下限。等 GitHub 淘汰 22.04 镜像时再往上抬一档。

同理 `libstdc++-12-dev` 是 22.04 上的包名，换镜像时要一起改。

### 3. macOS 只出 Apple Silicon

runner 是 `macos-14`（arm64），`flutter build macos` 默认只出当前架构，**不是 universal**。
需要覆盖 Intel Mac 的话，加一个 `macos-13` 的矩阵项，产物命名成 `-macos-x64` / `-macos-arm64`。

### 4. 没有代码签名和公证

* Windows：SmartScreen 会弹「Windows 已保护你的电脑」，要点「更多信息 → 仍要运行」。
* macOS：workflow 里做了 ad-hoc 签名（`codesign --force --deep --sign -`），
  能避免「文件已损坏，应移到废纸篓」，但 Gatekeeper 仍会拦，首次要右键 → 打开。

要正经签名：把证书放进仓库 Secrets，在打包步骤**之前**插入

* Windows：`signtool sign /fd SHA256 /tr <时间戳服务器> ...`
* macOS：`codesign --sign "Developer ID Application: ..."` + `xcrun notarytool submit --wait`
  + `xcrun stapler staple`

代价是每年的证书费（Windows OV/EV 证书、Apple 开发者账号）。个人项目不签也能用，
只是首次运行体验差一点，README 里说明一下即可。

### 5. release job 里的测试是软失败

`release.yml` 中的 `flutter analyze` / `flutter test` 带了 `continue-on-error: true`，
目的是测试环境抖动不至于挡住发版。质量门禁交给 `ci.yml`（严格模式）。
如果希望「测试不过就不许发版」，删掉那两行 `continue-on-error` 即可。

### 6. ci.yml 的格式检查很严

`dart format --output=none --set-exit-if-changed lib test tool` 只要有一个文件没格式化就红。
第一次接入前先本地跑一遍：

```bash
dart format lib test tool
```

嫌烦就把这一步删掉。

### 7. 权限与其他

* `release.yml` 声明了 `permissions: contents: write`，创建 Release 需要。
  如果仓库设置里 Actions 的默认权限是只读，这个声明是必需的。
* Release 默认是 **draft**（`draft: true`），不会立刻对外可见，改错了还能删。
  想直接发布就把它改成 `false`。
* 三个平台的构建是并行的，任何一个失败，`release` job 都不会跑（不会发出残缺的版本）。
* Windows 构建带插件需要符号链接权限——GitHub runner 上默认满足，
  只有本地开发才需要开「开发人员模式」。

## 本地复现打包

```bash
# Windows
flutter build windows --release --build-name=1.0.0
# 然后把 packaging/windows/setup.bat 和 assoc/ 拷到
# build/windows/x64/runner/Release/ 下

# Linux
flutter build linux --release --build-name=1.0.0
# 产物在 build/linux/x64/release/bundle/

# macOS
flutter build macos --release --build-name=1.0.0
# 产物在 build/macos/Build/Products/Release/lime-image.app
```
