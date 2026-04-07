#!/usr/bin/env swift
import AppKit
import Foundation

// Convert SVG to PNG at various sizes, then create .icns via iconutil

let scriptDir = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent().path
let svgPath = "\(scriptDir)/icon.svg"
let iconsetPath = "\(scriptDir)/AppIcon.iconset"
let icnsPath = "\(scriptDir)/AppIcon.icns"

// Required sizes for macOS .icns
let sizes: [(name: String, size: Int)] = [
    ("icon_16x16", 16),
    ("icon_16x16@2x", 32),
    ("icon_32x32", 32),
    ("icon_32x32@2x", 64),
    ("icon_128x128", 128),
    ("icon_128x128@2x", 256),
    ("icon_256x256", 256),
    ("icon_256x256@2x", 512),
    ("icon_512x512", 512),
    ("icon_512x512@2x", 1024),
]

// Load SVG
guard let svgData = FileManager.default.contents(atPath: svgPath) else {
    print("Error: Cannot read \(svgPath)")
    exit(1)
}

guard let svgImage = NSImage(data: svgData) else {
    print("Error: Cannot parse SVG")
    exit(1)
}

// Create iconset directory
try? FileManager.default.removeItem(atPath: iconsetPath)
try! FileManager.default.createDirectory(atPath: iconsetPath, withIntermediateDirectories: true)

// Render at each size
for (name, size) in sizes {
    let targetSize = NSSize(width: size, height: size)
    let image = NSImage(size: targetSize)
    image.lockFocus()
    svgImage.draw(in: NSRect(origin: .zero, size: targetSize),
                  from: NSRect(origin: .zero, size: svgImage.size),
                  operation: .copy,
                  fraction: 1.0)
    image.unlockFocus()

    guard let tiffData = image.tiffRepresentation,
          let bitmap = NSBitmapImageRep(data: tiffData),
          let pngData = bitmap.representation(using: .png, properties: [:])
    else {
        print("Error rendering \(name)")
        continue
    }

    let outPath = "\(iconsetPath)/\(name).png"
    try! pngData.write(to: URL(fileURLWithPath: outPath))
    print("  \(name).png (\(size)x\(size))")
}

// Convert iconset to icns
print("Creating .icns...")
let process = Process()
process.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
process.arguments = ["-c", "icns", iconsetPath, "-o", icnsPath]
try! process.run()
process.waitUntilExit()

if process.terminationStatus == 0 {
    print("Created: \(icnsPath)")
    // Clean up iconset
    try? FileManager.default.removeItem(atPath: iconsetPath)
} else {
    print("iconutil failed with status \(process.terminationStatus)")
}
