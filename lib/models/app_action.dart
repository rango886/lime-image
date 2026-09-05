import '../l10n/strings.dart';
import 'key_chord.dart';

enum ActionGroup {
  navigate('浏览'),
  zoom('缩放与平移'),
  mode('查看方式'),
  sort('排序'),
  file('文件'),
  image('图像'),
  anim('动图'),
  window('窗口'),
  ui('界面');

  const ActionGroup(this._label);
  final String _label;
  String get label => lt(_label);
}

/// 所有可绑定快捷键的动作
enum AppAction {
  nextImage('下一张', ActionGroup.navigate, ['arrowright']),
  prevImage('上一张', ActionGroup.navigate, ['arrowleft']),
  nextSingle('下一页（单页）', ActionGroup.navigate, ['shift+arrowright']),
  prevSingle('上一页（单页）', ActionGroup.navigate, ['shift+arrowleft']),
  firstImage('第一张', ActionGroup.navigate, ['home']),
  lastImage('最后一张', ActionGroup.navigate, ['end']),
  jumpForward('向后跳 10 张', ActionGroup.navigate, ['ctrl+arrowright']),
  jumpBackward('向前跳 10 张', ActionGroup.navigate, ['ctrl+arrowleft']),
  reload('重新载入', ActionGroup.navigate, ['f5']),

  zoomIn('放大', ActionGroup.zoom, ['equal']),
  zoomOut('缩小', ActionGroup.zoom, ['minus']),
  zoomOriginal('原始大小 100%', ActionGroup.zoom, ['0']),
  zoomFit('适应窗口', ActionGroup.zoom, ['shift+0']),
  scrollUp('向上滚动', ActionGroup.zoom, ['arrowup']),
  scrollDown('向下滚动', ActionGroup.zoom, ['arrowdown']),
  scrollLeft('向左滚动', ActionGroup.zoom, ['shift+arrowup']),
  scrollRight('向右滚动', ActionGroup.zoom, ['shift+arrowdown']),
  pageUp('上一屏', ActionGroup.zoom, ['pageup']),
  pageDown('下一屏', ActionGroup.zoom, ['pagedown']),

  mode1('自动缩放', ActionGroup.mode, ['1']),
  mode2('焦点缩放锁定', ActionGroup.mode, ['2']),
  mode3('宽度优先', ActionGroup.mode, ['3']),
  mode4('高度优先', ActionGroup.mode, ['4']),
  mode5('中心缩放锁定', ActionGroup.mode, ['5']),
  mode6('双页模式', ActionGroup.mode, ['6']),
  mode7('漫画模式', ActionGroup.mode, ['7']),
  mode8('长图模式', ActionGroup.mode, ['8']),

  sortNameAsc('按名称正序', ActionGroup.sort, ['n']),
  sortNameDesc('按名称逆序', ActionGroup.sort, ['shift+n']),
  sortTimeAsc('按时间正序', ActionGroup.sort, ['t']),
  sortTimeDesc('按时间逆序', ActionGroup.sort, ['shift+t']),
  sortSizeAsc('按大小正序', ActionGroup.sort, ['s']),
  sortSizeDesc('按大小逆序', ActionGroup.sort, ['shift+s']),
  sortRandom('随机顺序', ActionGroup.sort, ['shift+z']),

  openFile('打开图片…', ActionGroup.file, ['ctrl+o']),
  openFolder('打开文件夹…', ActionGroup.file, ['ctrl+shift+o']),
  revealInFolder('打开所在文件夹', ActionGroup.file, ['l']),
  toggleMark('标记 / 取消标记', ActionGroup.file, ['x']),
  showMarked('只浏览标记项', ActionGroup.file, ['shift+x']),
  copyMarked('复制标记项到…', ActionGroup.file, []),
  moveMarked('移动标记项到…', ActionGroup.file, []),
  deleteFile('删除文件', ActionGroup.file, ['delete']),
  renameFile('重命名…', ActionGroup.file, ['f2']),
  copyImage('复制图片', ActionGroup.file, ['ctrl+c']),
  copyPath('复制路径', ActionGroup.file, ['ctrl+shift+c']),
  pasteOpen('从剪贴板打开', ActionGroup.file, ['ctrl+v']),
  openWithSystem('用默认程序打开', ActionGroup.file, ['ctrl+enter']),

  rotateCW('顺时针旋转 90°', ActionGroup.image, ['r']),
  rotateCCW('逆时针旋转 90°', ActionGroup.image, ['shift+r']),
  flipHorizontal('水平翻转', ActionGroup.image, ['m']),
  flipVertical('垂直翻转', ActionGroup.image, ['shift+m']),
  resetTransform('重置变换', ActionGroup.image, ['ctrl+r']),

  animTogglePlay('暂停 / 播放动图', ActionGroup.anim, ['space']),
  animNextFrame('下一帧', ActionGroup.anim, ['period']),
  animPrevFrame('上一帧', ActionGroup.anim, ['comma']),
  animSlower('减速', ActionGroup.anim, []),
  animFaster('加速', ActionGroup.anim, []),

  toggleFullscreen('全屏', ActionGroup.window, ['f11']),
  closeWindow('关闭窗口', ActionGroup.window, ['escape']),
  minimizeWindow('最小化', ActionGroup.window, []),
  toggleMaximize('最大化 / 还原', ActionGroup.window, ['ctrl+m']),
  toggleAlwaysOnTop('窗口置顶', ActionGroup.window, ['ctrl+shift+t']),
  fitWindowToImage('窗口适应图片', ActionGroup.window, ['ctrl+shift+w']),

  toggleFilmstrip('缩略图栏', ActionGroup.ui, ['b']),
  toggleStatusPanel('状态悬浮窗', ActionGroup.ui, ['h']),
  toggleGrid('网格总览', ActionGroup.ui, ['g']),
  toggleSlideshow('幻灯片放映', ActionGroup.ui, ['p']),
  toggleTheme('切换亮 / 暗主题', ActionGroup.ui, ['ctrl+t']),
  openSettings('设置', ActionGroup.ui, ['f12']),
  showHelp('帮助', ActionGroup.ui, ['f1']);

  const AppAction(this._label, this.group, this.defaultChords);
  final String _label;
  String get label => lt(_label);
  final ActionGroup group;
  final List<String> defaultChords;

  List<KeyChord> get defaults =>
      defaultChords.map(KeyChord.parse).whereType<KeyChord>().toList();
}

AppAction? actionFromName(String name) {
  for (final a in AppAction.values) {
    if (a.name == name) return a;
  }
  return null;
}
