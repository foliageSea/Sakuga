import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  private var imageClipboardChannel: FlutterMethodChannel?

  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)
    RegisterGeneratedPlugins(registry: flutterViewController)
    let channel = FlutterMethodChannel(
      name: "com.foliage.sakuga/image_clipboard",
      binaryMessenger: flutterViewController.engine.binaryMessenger)
    imageClipboardChannel = channel
    channel.setMethodCallHandler { call, result in
      guard call.method == "writePng" else {
        result(FlutterMethodNotImplemented)
        return
      }
      guard let bytes = call.arguments as? FlutterStandardTypedData,
        bytes.data.starts(with: [137, 80, 78, 71, 13, 10, 26, 10]),
        NSImage(data: bytes.data) != nil
      else {
        result(FlutterError(code: "invalid_png", message: "Expected PNG image bytes.", details: nil))
        return
      }
      let pasteboard = NSPasteboard.general
      pasteboard.clearContents()
      guard pasteboard.setData(bytes.data, forType: .png) else {
        result(FlutterError(
          code: "clipboard_write_failed", message: "Could not write image to clipboard.", details: nil))
        return
      }
      result(nil)
    }
    super.awakeFromNib()
  }
}
