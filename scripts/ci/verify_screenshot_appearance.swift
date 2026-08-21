#!/usr/bin/env swift
import AppKit
import Foundation

enum AppearanceVerificationError: Error, CustomStringConvertible {
    case usage
    case unreadableImage(String)
    case noSamples(String)

    var description: String {
        switch self {
        case .usage:
            return "Usage: verify_screenshot_appearance.swift <light.png> <dark.png>"
        case .unreadableImage(let path):
            return "Could not decode screenshot: \(path)"
        case .noSamples(let path):
            return "Screenshot produced no corner background samples: \(path)"
        }
    }
}

func cornerBackgroundLuminance(path: String) throws -> Double {
    let url = URL(fileURLWithPath: path)
    let data = try Data(contentsOf: url)
    guard let bitmap = NSBitmapImageRep(data: data) else {
        throw AppearanceVerificationError.unreadableImage(path)
    }

    let width = bitmap.pixelsWide
    let height = bitmap.pixelsHigh
    let centers = [
        (max(1, Int(Double(width) * 0.02)), max(1, Int(Double(height) * 0.02))),
        (min(width - 2, Int(Double(width) * 0.98)), max(1, Int(Double(height) * 0.02))),
        (max(1, Int(Double(width) * 0.02)), min(height - 2, Int(Double(height) * 0.98))),
        (min(width - 2, Int(Double(width) * 0.98)), min(height - 2, Int(Double(height) * 0.98)))
    ]

    let radius = 8
    var total = 0.0
    var count = 0
    for (centerX, centerY) in centers {
        for y in max(0, centerY - radius)...min(height - 1, centerY + radius) {
            for x in max(0, centerX - radius)...min(width - 1, centerX + radius) {
                guard let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else { continue }
                total += 0.2126 * color.redComponent
                    + 0.7152 * color.greenComponent
                    + 0.0722 * color.blueComponent
                count += 1
            }
        }
    }

    guard count > 0 else {
        throw AppearanceVerificationError.noSamples(path)
    }
    return total / Double(count)
}

func fail(_ message: String, code: Int32) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(code)
}

do {
    guard CommandLine.arguments.count == 3 else {
        throw AppearanceVerificationError.usage
    }

    let light = try cornerBackgroundLuminance(path: CommandLine.arguments[1])
    let dark = try cornerBackgroundLuminance(path: CommandLine.arguments[2])
    let delta = light - dark
    print(String(format: "light_corner_luminance=%.4f", light))
    print(String(format: "dark_corner_luminance=%.4f", dark))
    print(String(format: "delta=%.4f", delta))

    if light < 0.75 {
        fail("Invalid light-mode evidence: corner background is not light.", code: 10)
    }
    if dark > 0.35 {
        fail("Invalid dark-mode evidence: corner background is not dark.", code: 11)
    }
    if delta < 0.40 {
        fail("Invalid appearance evidence: rendered light/dark separation is too small.", code: 12)
    }
} catch {
    fail("Appearance verification failed: \(error)", code: 13)
}
