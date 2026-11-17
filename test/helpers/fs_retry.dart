import 'dart:io';

/// Windows 上刚写完的文件可能被杀毒 / 索引服务短暂占用（共享冲突），
/// 递归删除临时目录时偶发 errno 32。退避重试几次；实在删不掉就放弃——
/// 清理失败不该拖垮测试结果，系统临时目录反正会被定期清理。
Future<void> deleteTempDir(Directory dir) async {
  for (var attempt = 0; ; attempt++) {
    try {
      await dir.delete(recursive: true);
      return;
    } on FileSystemException catch (e) {
      if (attempt >= 8) {
        // ignore: avoid_print
        print('清理临时目录失败（忽略）: ${dir.path} — ${e.message}');
        return;
      }
      await Future<void>.delayed(Duration(milliseconds: 50 * (attempt + 1)));
    }
  }
}
