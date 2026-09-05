import Cocoa
import FlutterMacOS

@main
class AppDelegate: FlutterAppDelegate {
  /// Flutter 端还没起来时先把待打开的文件缓存住
  private var pendingFiles: [String] = []
  private var channel: FlutterMethodChannel?

  override func applicationDidFinishLaunching(_ notification: Notification) {
    if let controller = mainFlutterWindow?.contentViewController as? FlutterViewController {
      let ch = FlutterMethodChannel(
        name: "limeimage/platform",
        binaryMessenger: controller.engine.binaryMessenger)
      ch.setMethodCallHandler { [weak self] call, result in
        if call.method == "consumePendingFiles" {
          let files = self?.pendingFiles ?? []
          self?.pendingFiles = []
          result(files)
        } else {
          result(FlutterMethodNotImplemented)
        }
      }
      channel = ch
      flushPending()
    }
    super.applicationDidFinishLaunching(notification)
  }

  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    return true
  }

  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return true
  }

  // Finder 双击 / 拖到 Dock 图标 / open 命令：macOS 走 Apple Event，不是 argv
  override func application(_ sender: NSApplication, open urls: [URL]) {
    let paths = urls.filter { $0.isFileURL }.map { $0.path }
    guard !paths.isEmpty else { return }
    pendingFiles.append(contentsOf: paths)
    flushPending()
    NSApp.activate(ignoringOtherApps: true)
  }

  override func application(_ sender: NSApplication, openFile filename: String) -> Bool {
    pendingFiles.append(filename)
    flushPending()
    return true
  }

  override func application(_ sender: NSApplication, openFiles filenames: [String]) {
    pendingFiles.append(contentsOf: filenames)
    flushPending()
  }

  private func flushPending() {
    guard let channel = channel, !pendingFiles.isEmpty else { return }
    let files = pendingFiles
    pendingFiles = []
    channel.invokeMethod("openFiles", arguments: files)
  }
}
