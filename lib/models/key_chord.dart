import 'package:flutter/services.dart';

/// 一个快捷键组合。序列化成 "ctrl+shift+n" 这样的人类可读文本。
class KeyChord {
  const KeyChord(
    this.keyId, {
    this.ctrl = false,
    this.shift = false,
    this.alt = false,
    this.meta = false,
  });

  final int keyId;
  final bool ctrl;
  final bool shift;
  final bool alt;
  final bool meta;

  factory KeyChord.fromEvent(KeyEvent event) {
    final k = HardwareKeyboard.instance;
    return KeyChord(
      _normalizeId(event.logicalKey.keyId),
      ctrl: k.isControlPressed,
      shift: k.isShiftPressed,
      alt: k.isAltPressed,
      meta: k.isMetaPressed,
    );
  }

  /// 中文输入法开启时，logicalKey 可能被 IME 改写成别的字符，
  /// 这里用物理按键（USB HID usage，等价于美式键盘布局）再匹配一次。
  static KeyChord? fromPhysical(KeyEvent event) {
    final id = _physicalToLogical[event.physicalKey.usbHidUsage];
    if (id == null) return null;
    final k = HardwareKeyboard.instance;
    return KeyChord(
      id,
      ctrl: k.isControlPressed,
      shift: k.isShiftPressed,
      alt: k.isAltPressed,
      meta: k.isMetaPressed,
    );
  }

  /// USB HID usage -> 逻辑键 id（美式布局）
  static final Map<int, int> _physicalToLogical =
      {
        for (var i = 0; i < 26; i++) 0x00070004 + i: 0x61 + i, // a..z
        for (var i = 0; i < 9; i++) 0x0007001e + i: 0x31 + i, // 1..9
        0x00070027: 0x30, // 0
      }..addAll({
        0x00070028: LogicalKeyboardKey.enter.keyId,
        0x00070029: LogicalKeyboardKey.escape.keyId,
        0x0007002a: LogicalKeyboardKey.backspace.keyId,
        0x0007002b: LogicalKeyboardKey.tab.keyId,
        0x0007002c: LogicalKeyboardKey.space.keyId,
        0x0007002d: LogicalKeyboardKey.minus.keyId,
        0x0007002e: LogicalKeyboardKey.equal.keyId,
        0x0007002f: LogicalKeyboardKey.bracketLeft.keyId,
        0x00070030: LogicalKeyboardKey.bracketRight.keyId,
        0x00070031: LogicalKeyboardKey.backslash.keyId,
        0x00070033: LogicalKeyboardKey.semicolon.keyId,
        0x00070034: LogicalKeyboardKey.quote.keyId,
        0x00070035: LogicalKeyboardKey.backquote.keyId,
        0x00070036: LogicalKeyboardKey.comma.keyId,
        0x00070037: LogicalKeyboardKey.period.keyId,
        0x00070038: LogicalKeyboardKey.slash.keyId,
        0x0007003a: LogicalKeyboardKey.f1.keyId,
        0x0007003b: LogicalKeyboardKey.f2.keyId,
        0x0007003c: LogicalKeyboardKey.f3.keyId,
        0x0007003d: LogicalKeyboardKey.f4.keyId,
        0x0007003e: LogicalKeyboardKey.f5.keyId,
        0x0007003f: LogicalKeyboardKey.f6.keyId,
        0x00070040: LogicalKeyboardKey.f7.keyId,
        0x00070041: LogicalKeyboardKey.f8.keyId,
        0x00070042: LogicalKeyboardKey.f9.keyId,
        0x00070043: LogicalKeyboardKey.f10.keyId,
        0x00070044: LogicalKeyboardKey.f11.keyId,
        0x00070045: LogicalKeyboardKey.f12.keyId,
        0x00070049: LogicalKeyboardKey.insert.keyId,
        0x0007004a: LogicalKeyboardKey.home.keyId,
        0x0007004b: LogicalKeyboardKey.pageUp.keyId,
        0x0007004c: LogicalKeyboardKey.delete.keyId,
        0x0007004d: LogicalKeyboardKey.end.keyId,
        0x0007004e: LogicalKeyboardKey.pageDown.keyId,
        0x0007004f: LogicalKeyboardKey.arrowRight.keyId,
        0x00070050: LogicalKeyboardKey.arrowLeft.keyId,
        0x00070051: LogicalKeyboardKey.arrowDown.keyId,
        0x00070052: LogicalKeyboardKey.arrowUp.keyId,
        0x00070057: LogicalKeyboardKey.equal.keyId, // numpad +
        0x00070056: LogicalKeyboardKey.minus.keyId, // numpad -
        0x00070058: LogicalKeyboardKey.enter.keyId, // numpad enter
      });

  static int _normalizeId(int id) => _aliases[id] ?? id;

  /// 小键盘 / 变体键归一化
  static final Map<int, int> _aliases = {
    LogicalKeyboardKey.numpadAdd.keyId: LogicalKeyboardKey.equal.keyId,
    LogicalKeyboardKey.add.keyId: LogicalKeyboardKey.equal.keyId,
    LogicalKeyboardKey.numpadSubtract.keyId: LogicalKeyboardKey.minus.keyId,
    LogicalKeyboardKey.numpadEnter.keyId: LogicalKeyboardKey.enter.keyId,
    LogicalKeyboardKey.numpad0.keyId: LogicalKeyboardKey.digit0.keyId,
    LogicalKeyboardKey.numpad1.keyId: LogicalKeyboardKey.digit1.keyId,
    LogicalKeyboardKey.numpad2.keyId: LogicalKeyboardKey.digit2.keyId,
    LogicalKeyboardKey.numpad3.keyId: LogicalKeyboardKey.digit3.keyId,
    LogicalKeyboardKey.numpad4.keyId: LogicalKeyboardKey.digit4.keyId,
    LogicalKeyboardKey.numpad5.keyId: LogicalKeyboardKey.digit5.keyId,
    LogicalKeyboardKey.numpad6.keyId: LogicalKeyboardKey.digit6.keyId,
    LogicalKeyboardKey.numpad7.keyId: LogicalKeyboardKey.digit7.keyId,
    LogicalKeyboardKey.numpad8.keyId: LogicalKeyboardKey.digit8.keyId,
    LogicalKeyboardKey.numpad9.keyId: LogicalKeyboardKey.digit9.keyId,
  };

  static final Map<String, LogicalKeyboardKey> _named = {
    'arrowleft': LogicalKeyboardKey.arrowLeft,
    'arrowright': LogicalKeyboardKey.arrowRight,
    'arrowup': LogicalKeyboardKey.arrowUp,
    'arrowdown': LogicalKeyboardKey.arrowDown,
    'home': LogicalKeyboardKey.home,
    'end': LogicalKeyboardKey.end,
    'pageup': LogicalKeyboardKey.pageUp,
    'pagedown': LogicalKeyboardKey.pageDown,
    'escape': LogicalKeyboardKey.escape,
    'enter': LogicalKeyboardKey.enter,
    'space': LogicalKeyboardKey.space,
    'tab': LogicalKeyboardKey.tab,
    'backspace': LogicalKeyboardKey.backspace,
    'delete': LogicalKeyboardKey.delete,
    'insert': LogicalKeyboardKey.insert,
    'equal': LogicalKeyboardKey.equal,
    'minus': LogicalKeyboardKey.minus,
    'bracketleft': LogicalKeyboardKey.bracketLeft,
    'bracketright': LogicalKeyboardKey.bracketRight,
    'comma': LogicalKeyboardKey.comma,
    'period': LogicalKeyboardKey.period,
    'slash': LogicalKeyboardKey.slash,
    'backslash': LogicalKeyboardKey.backslash,
    'semicolon': LogicalKeyboardKey.semicolon,
    'quote': LogicalKeyboardKey.quote,
    'backquote': LogicalKeyboardKey.backquote,
    'f1': LogicalKeyboardKey.f1,
    'f2': LogicalKeyboardKey.f2,
    'f3': LogicalKeyboardKey.f3,
    'f4': LogicalKeyboardKey.f4,
    'f5': LogicalKeyboardKey.f5,
    'f6': LogicalKeyboardKey.f6,
    'f7': LogicalKeyboardKey.f7,
    'f8': LogicalKeyboardKey.f8,
    'f9': LogicalKeyboardKey.f9,
    'f10': LogicalKeyboardKey.f10,
    'f11': LogicalKeyboardKey.f11,
    'f12': LogicalKeyboardKey.f12,
    for (var c = 0x61; c <= 0x7a; c++)
      String.fromCharCode(c): LogicalKeyboardKey(c),
    for (var c = 0x30; c <= 0x39; c++)
      String.fromCharCode(c): LogicalKeyboardKey(c),
  };

  static final Map<int, String> _reverse = {
    for (final e in _named.entries) e.value.keyId: e.key,
  };

  static String? _nameOf(int id) => _reverse[id];

  String encode() {
    final parts = <String>[];
    if (ctrl) parts.add('ctrl');
    if (shift) parts.add('shift');
    if (alt) parts.add('alt');
    if (meta) parts.add('meta');
    parts.add(_nameOf(keyId) ?? '0x${keyId.toRadixString(16)}');
    return parts.join('+');
  }

  static KeyChord? parse(String? text) {
    if (text == null || text.trim().isEmpty) return null;
    final parts = text.toLowerCase().split('+').map((e) => e.trim()).toList();
    bool ctrl = false, shift = false, alt = false, meta = false;
    String? keyPart;
    for (final part in parts) {
      switch (part) {
        case 'ctrl':
        case 'control':
          ctrl = true;
        case 'shift':
          shift = true;
        case 'alt':
        case 'option':
          alt = true;
        case 'meta':
        case 'cmd':
        case 'super':
        case 'win':
          meta = true;
        default:
          keyPart = part;
      }
    }
    if (keyPart == null) return null;
    int? id;
    if (keyPart.startsWith('0x')) {
      id = int.tryParse(keyPart.substring(2), radix: 16);
    } else {
      id = _named[keyPart]?.keyId;
    }
    if (id == null) return null;
    return KeyChord(
      _normalizeId(id),
      ctrl: ctrl,
      shift: shift,
      alt: alt,
      meta: meta,
    );
  }

  /// 界面显示用
  String get label {
    final parts = <String>[];
    if (ctrl) parts.add('Ctrl');
    if (shift) parts.add('Shift');
    if (alt) parts.add('Alt');
    if (meta) parts.add('Cmd');
    final name = _nameOf(keyId) ?? '0x${keyId.toRadixString(16)}';
    parts.add(
      _pretty[name] ?? (name.length == 1 ? name.toUpperCase() : _cap(name)),
    );
    return parts.join('+');
  }

  static String _cap(String s) =>
      s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);

  static const _pretty = {
    'arrowleft': '←',
    'arrowright': '→',
    'arrowup': '↑',
    'arrowdown': '↓',
    'escape': 'Esc',
    'space': 'Space',
    'pageup': 'PgUp',
    'pagedown': 'PgDn',
    'equal': '+',
    'minus': '-',
    'comma': ',',
    'period': '.',
    'delete': 'Del',
  };

  @override
  bool operator ==(Object other) =>
      other is KeyChord &&
      other.keyId == keyId &&
      other.ctrl == ctrl &&
      other.shift == shift &&
      other.alt == alt &&
      other.meta == meta;

  @override
  int get hashCode => Object.hash(keyId, ctrl, shift, alt, meta);

  @override
  String toString() => encode();
}
