import '../l10n/strings.dart';

/// 8 种查看方式
enum ViewMode {
  autoFit('自动缩放', '1'),
  focusLock('焦点缩放锁定', '2'),
  fitWidth('宽度优先', '3'),
  fitHeight('高度优先', '4'),
  centerLock('中心缩放锁定', '5'),
  doublePage('双页模式', '6'),
  comic('漫画模式', '7'),
  longStrip('长图模式', '8');

  const ViewMode(this._label, this.hint);
  final String _label;
  String get label => lt(_label);
  final String hint;

  bool get isScrollMode => this == ViewMode.comic || this == ViewMode.longStrip;
}

enum SortField {
  name('名称'),
  time('修改时间'),
  size('大小'),
  type('类型'),
  random('随机');

  const SortField(this._label);
  final String _label;
  String get label => lt(_label);
}

/// 滚轮 / 手势可绑定的动作
enum WheelAction {
  none('无'),
  switchImage('切换图片'),
  switchSingle('切换单页'),
  zoom('缩放'),
  scrollVertical('垂直滚动'),
  scrollHorizontal('水平滚动');

  const WheelAction(this._label);
  final String _label;
  String get label => lt(_label);
}

enum DragButton {
  left('左键'),
  middle('中键'),
  right('右键');

  const DragButton(this._label);
  final String _label;
  String get label => lt(_label);
}

enum TransitionType {
  none('无'),
  fade('淡入淡出'),
  slide('水平滑动'),
  scale('缩放淡入'),
  slideVertical('垂直滑动');

  const TransitionType(this._label);
  final String _label;
  String get label => lt(_label);
}

enum BackgroundStyle {
  theme('跟随主题'),
  black('纯黑'),
  dark('深灰'),
  light('浅灰'),
  white('纯白'),
  checker('棋盘格');

  const BackgroundStyle(this._label);
  final String _label;
  String get label => lt(_label);
}

enum ThemePref {
  system('跟随系统'),
  light('亮色'),
  dark('暗色');

  const ThemePref(this._label);
  final String _label;
  String get label => lt(_label);
}

enum InstanceMode {
  reuse('复用已有窗口'),
  newWindow('每次打开新窗口');

  const InstanceMode(this._label);
  final String _label;
  String get label => lt(_label);
}

enum Interpolation {
  auto('自动（交互中降质）'),
  none('最近邻（像素画）'),
  low('低'),
  medium('中'),
  high('高');

  const Interpolation(this._label);
  final String _label;
  String get label => lt(_label);
}

enum StartupPlacement {
  center('居中并使用默认尺寸'),
  remember('记住上次位置和大小');

  const StartupPlacement(this._label);
  final String _label;
  String get label => lt(_label);
}

enum DoubleClickAction {
  toggleFullscreen('切换全屏'),
  toggleZoom('原始大小 / 适应窗口'),
  maximize('最大化'),
  nextImage('下一张'),
  none('无');

  const DoubleClickAction(this._label);
  final String _label;
  String get label => lt(_label);
}

enum ReadingDirection {
  ltr('从左到右'),
  rtl('从右到左（日漫）');

  const ReadingDirection(this._label);
  final String _label;
  String get label => lt(_label);
}

/// 悬浮状态窗的位置
enum PanelCorner {
  topLeft('左上'),
  topRight('右上'),
  bottomLeft('左下'),
  bottomRight('右下');

  const PanelCorner(this._label);
  final String _label;
  String get label => lt(_label);
}

T enumFromName<T extends Enum>(List<T> values, Object? name, T fallback) {
  if (name is! String) return fallback;
  for (final v in values) {
    if (v.name == name) return v;
  }
  return fallback;
}
