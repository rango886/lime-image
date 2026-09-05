import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

/// 与系统交互的杂项操作（回收站 / 文件管理器 / 单实例 / macOS 打开文件事件）
class PlatformOps {
  PlatformOps._();

  static const _channel = MethodChannel('limeimage/platform');

  /// macOS: Finder 双击、拖到 Dock 图标打开文件时由原生侧推送过来
  static final StreamController<List<String>> _openFiles =
      StreamController<List<String>>.broadcast();
  static Stream<List<String>> get openFileEvents => _openFiles.stream;

  static void emitOpenFiles(List<String> paths) {
    if (paths.isNotEmpty) _openFiles.add(paths);
  }

  static void initChannel() {
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'openFiles') {
        final list = (call.arguments as List?)?.cast<String>() ?? const [];
        emitOpenFiles(list);
      }
      return null;
    });
    // 启动早期原生侧缓存的待打开文件
    if (Platform.isMacOS) {
      _channel
          .invokeMethod<List<Object?>>('consumePendingFiles')
          .then((v) {
            if (v != null) emitOpenFiles(v.cast<String>());
          })
          .catchError((_) => null);
    }
  }

  // —— 输入法 ——
  static bool _imeEnabled = false;
  static int _imeRequests = 0;

  /// 打开/关闭窗口的输入法。关闭后中文输入法不会再吞掉单键快捷键。
  static Future<void> setImeEnabled(bool enabled) async {
    if (_imeEnabled == enabled) return;
    _imeEnabled = enabled;
    try {
      await _channel.invokeMethod<void>('setImeEnabled', enabled);
    } catch (_) {
      // 其他平台没有实现，忽略
    }
  }

  /// 文本框获得焦点时调用（可嵌套）
  static void acquireIme() {
    _imeRequests++;
    if (_imeRequests == 1) setImeEnabled(true);
  }

  /// 文本框销毁时调用
  static void releaseIme() {
    if (_imeRequests > 0) _imeRequests--;
    if (_imeRequests == 0) setImeEnabled(false);
  }

  /// 删除到回收站（失败时返回 false，调用方可退回硬删除）
  static Future<bool> moveToTrash(String path) async {
    try {
      if (Platform.isWindows) {
        final script =
            '''
Add-Type -AssemblyName Microsoft.VisualBasic
[Microsoft.VisualBasic.FileIO.FileSystem]::DeleteFile('${path.replaceAll("'", "''")}','OnlyErrorDialogs','SendToRecycleBin')
''';
        final r = await Process.run('powershell', [
          '-NoProfile',
          '-Command',
          script,
        ]);
        return r.exitCode == 0;
      } else if (Platform.isMacOS) {
        final r = await Process.run('osascript', [
          '-e',
          'tell application "Finder" to delete POSIX file "${path.replaceAll('"', '\\"')}"',
        ]);
        return r.exitCode == 0;
      } else {
        final r = await Process.run('gio', ['trash', path]);
        if (r.exitCode == 0) return true;
        final r2 = await Process.run('trash-put', [path]);
        return r2.exitCode == 0;
      }
    } catch (_) {
      return false;
    }
  }

  /// 在文件管理器中定位文件
  static Future<void> revealInFileManager(String path) async {
    try {
      if (Platform.isWindows) {
        await Process.run('explorer.exe', ['/select,', path]);
      } else if (Platform.isMacOS) {
        await Process.run('open', ['-R', path]);
      } else {
        final ok = await Process.run('dbus-send', [
          '--session',
          '--dest=org.freedesktop.FileManager1',
          '--type=method_call',
          '/org/freedesktop/FileManager1',
          'org.freedesktop.FileManager1.ShowItems',
          'array:string:file://$path',
          'string:',
        ]);
        if (ok.exitCode != 0) {
          await Process.run('xdg-open', [p.dirname(path)]);
        }
      }
    } catch (_) {}
  }

  /// 用系统默认程序打开
  static Future<void> openWithSystem(String path) async {
    try {
      if (Platform.isWindows) {
        await Process.run('cmd', ['/c', 'start', '', path]);
      } else if (Platform.isMacOS) {
        await Process.run('open', [path]);
      } else {
        await Process.run('xdg-open', [path]);
      }
    } catch (_) {}
  }

  /// 复制文本到剪贴板
  static Future<void> copyText(String text) =>
      Clipboard.setData(ClipboardData(text: text));

  /// 把文件放进系统剪贴板（图片本体）。纯 Dart 只能做到平台命令级别。
  static Future<bool> copyImageToClipboard(String path) async {
    try {
      if (Platform.isWindows) {
        final script =
            "Add-Type -AssemblyName System.Windows.Forms,System.Drawing; "
            "\$img=[System.Drawing.Image]::FromFile('${path.replaceAll("'", "''")}'); "
            "[System.Windows.Forms.Clipboard]::SetImage(\$img); \$img.Dispose()";
        final r = await Process.run('powershell', [
          '-NoProfile',
          '-STA',
          '-Command',
          script,
        ]);
        return r.exitCode == 0;
      } else if (Platform.isMacOS) {
        final r = await Process.run('osascript', [
          '-e',
          'set the clipboard to (read (POSIX file "${path.replaceAll('"', '\\"')}") as JPEG picture)',
        ]);
        return r.exitCode == 0;
      } else {
        final mime = _mimeOf(path);
        final r = await Process.run('sh', [
          '-c',
          'xclip -selection clipboard -t $mime -i "$path"',
        ]);
        return r.exitCode == 0;
      }
    } catch (_) {
      return false;
    }
  }

  /// 从剪贴板读取文件路径（多数文件管理器复制文件后为文本或 uri-list）
  static Future<String?> clipboardImagePath() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    var text = data?.text?.trim();
    if (text == null || text.isEmpty) return null;
    text = text.split('\n').first.trim();
    if (text.startsWith('file://')) {
      text = Uri.parse(text).toFilePath();
    }
    text = text.replaceAll('"', '');
    if (await File(text).exists()) return text;
    return null;
  }

  static String _mimeOf(String path) {
    switch (p.extension(path).toLowerCase()) {
      case '.png':
        return 'image/png';
      case '.gif':
        return 'image/gif';
      case '.webp':
        return 'image/webp';
      case '.bmp':
        return 'image/bmp';
      default:
        return 'image/jpeg';
    }
  }
}

/// ---------------------------------------------------------------------------
/// 单实例支持：本地端口做互斥锁 + 传递待打开文件
/// ---------------------------------------------------------------------------
class SingleInstance {
  SingleInstance._();

  static ServerSocket? _server;

  /// 尝试成为主实例。成功返回 true；已有实例则把参数发过去并返回 false。
  static Future<bool> acquire(
    List<String> args, {
    required void Function(List<String>) onSecondInstance,
    int port = 47823,
  }) async {
    try {
      _server = await ServerSocket.bind(InternetAddress.loopbackIPv4, port);
    } on SocketException {
      try {
        final s = await Socket.connect(
          InternetAddress.loopbackIPv4,
          port,
          timeout: const Duration(seconds: 2),
        );
        s.write(jsonEncode({'args': args}));
        await s.flush();
        await s.close();
      } catch (_) {
        // 端口被别的程序占用，就当自己是主实例
        return true;
      }
      return false;
    }
    _server!.listen((client) {
      final buf = <int>[];
      client.listen(
        buf.addAll,
        onDone: () {
          try {
            final msg = jsonDecode(utf8.decode(buf)) as Map<String, dynamic>;
            onSecondInstance(
              (msg['args'] as List?)?.cast<String>() ?? const [],
            );
          } catch (_) {}
          client.destroy();
        },
      );
    });
    return true;
  }

  static Future<void> release() async {
    await _server?.close();
    _server = null;
  }
}
