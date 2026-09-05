import 'package:flutter_test/flutter_test.dart';
import 'package:limeimage/core/utils.dart';
import 'package:limeimage/models/key_chord.dart';

void main() {
  test('自然排序', () {
    final list = ['img10.jpg', 'img2.jpg', 'img1.jpg'];
    list.sort(naturalCompare);
    expect(list, ['img1.jpg', 'img2.jpg', 'img10.jpg']);
  });

  test('快捷键编码往返', () {
    final c = KeyChord.parse('ctrl+shift+n')!;
    expect(c.encode(), 'ctrl+shift+n');
    expect(c.label, 'Ctrl+Shift+N');
    expect(KeyChord.parse('arrowleft')!.label, '←');
  });

  test('格式识别', () {
    expect(isImageFile('a.PNG'), true);
    expect(isImageFile('a.txt'), false);
    expect(isArchiveFile('a.cbz'), true);
  });
}
