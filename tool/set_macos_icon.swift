import AppKit

// Use Finder custom icon metadata for the DMG file itself.
guard CommandLine.arguments.count == 3,
      let icon = NSImage(contentsOfFile: CommandLine.arguments[1]) else {
    fputs("Usage: swift set_macos_icon.swift <icon.icns> <target>\n", stderr)
    exit(1)
}

guard NSWorkspace.shared.setIcon(
    icon, forFile: CommandLine.arguments[2], options: []
) else {
    fputs("Failed to set the macOS custom icon.\n", stderr)
    exit(1)
}
