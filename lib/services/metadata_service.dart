import 'dart:io';
import 'dart:isolate';

import '../models/image_metadata.dart';
import 'metadata/reader.dart';
export 'metadata/reader.dart' show readImageMetadata;
export 'metadata/xmp.dart' show parseXmp;

/// Compatibility entry point; dispatches by signature, not filename extension.
Future<ImageMetadata> readJpegMetadata(String path) => readImageMetadata(path);

/// Independent from pixel decoding. One active worker and a small stat-keyed LRU.
class MetadataService {
  final _cache = <String, ImageMetadata>{};
  Future<void> _tail = Future.value();
  int _ticket = 0;

  void cancel() => _ticket++;

  Future<ImageMetadata?> load(String path) async {
    final ticket = ++_ticket;
    final previous = _tail;
    final done = _load(previous, path, ticket);
    _tail = done.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return done;
  }

  Future<ImageMetadata?> _load(
    Future<void> previous,
    String path,
    int ticket,
  ) async {
    await previous;
    if (ticket != _ticket) return null;
    try {
      final stat = await File(path).stat();
      if (ticket != _ticket) return null;
      final key = '$path|${stat.size}|${stat.modified.microsecondsSinceEpoch}';
      final hit = _cache.remove(key);
      if (hit != null) {
        _cache[key] = hit;
        return hit;
      }
      final result = await Isolate.run(() => readImageMetadata(path));
      if (ticket != _ticket) return null;
      _cache[key] = result;
      while (_cache.length > 16) {
        _cache.remove(_cache.keys.first);
      }
      return result;
    } catch (e) {
      return ImageMetadata(warnings: ['读取失败：$e']);
    }
  }
}
