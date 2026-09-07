import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:limeimage/core/donation.dart';

void main() {
  test('内嵌二维码是合法 PNG', () async {
    for (final entry in {
      'alipay': alipayQrBytes,
      'wechat': wechatQrBytes,
    }.entries) {
      final bytes = entry.value;
      expect(
        bytes.sublist(0, 8),
        [137, 80, 78, 71, 13, 10, 26, 10],
        reason: entry.key,
      );
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      expect(frame.image.width, greaterThan(0), reason: entry.key);
      expect(frame.image.height, greaterThan(0), reason: entry.key);
    }
  });

  test('赞助信息与 WPF 版本一致', () {
    expect(kProjectUrl, 'https://github.com/rango886/lime-image');
    expect(kProjectAuthor, '李志平');
    expect(kBtcAddress, '1Mu7RNd5KiJmCmsezX86wckT6DHnQuj69p');
    expect(kEthAddress, '0x4b60173978fec8cc05787488c98f43d45910e123');
  });
}
