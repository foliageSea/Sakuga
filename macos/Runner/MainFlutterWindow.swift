import Cocoa
import FlutterMacOS
import IOKit

class MainFlutterWindow: NSWindow {
  private var imageClipboardChannel: FlutterMethodChannel?
  private var gpuUsageChannel: FlutterMethodChannel?

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
    let gpuChannel = FlutterMethodChannel(
      name: "com.foliage.sakuga/gpu_usage",
      binaryMessenger: flutterViewController.engine.binaryMessenger)
    gpuUsageChannel = gpuChannel
    gpuChannel.setMethodCallHandler { call, result in
      guard call.method == "read" else {
        result(FlutterMethodNotImplemented)
        return
      }
      var iterator: io_iterator_t = 0
      guard IOServiceGetMatchingServices(
        kIOMainPortDefault, IOServiceMatching("IOAccelerator"), &iterator
      ) == KERN_SUCCESS else {
        result(nil)
        return
      }
      defer { IOObjectRelease(iterator) }
      var maxUtilization: Int?
      while case let service = IOIteratorNext(iterator), service != 0 {
        defer { IOObjectRelease(service) }
        guard let stats = IORegistryEntryCreateCFProperty(
          service, "PerformanceStatistics" as CFString, kCFAllocatorDefault, 0
        )?.takeRetainedValue() as? [String: Any] else { continue }
        let raw = (stats["Device Utilization %"] as? NSNumber)?.intValue
          ?? (stats["GPU Activity(%)"] as? NSNumber)?.intValue
          ?? (stats["Renderer Utilization %"] as? NSNumber)?.intValue
        guard let value = raw else { continue }
        let clamped = min(max(value, 0), 100)
        maxUtilization = max(maxUtilization ?? clamped, clamped)
      }
      result(maxUtilization)
    }
    super.awakeFromNib()
  }
}
