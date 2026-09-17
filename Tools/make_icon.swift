// Generates Resources/AppIcon.icns for Emulator Studio.
// Run:  swift Tools/make_icon.swift
import AppKit
import Foundation

let canvas: CGFloat = 1024
let image = NSImage(size: NSSize(width: canvas, height: canvas))
image.lockFocus()

guard let ctx = NSGraphicsContext.current?.cgContext else { exit(1) }

// ── Background ────────────────────────────────────────────────────────────
let inset: CGFloat = 62
let bgRect = NSRect(x: inset, y: inset, width: canvas - inset * 2, height: canvas - inset * 2)
let bgPath = NSBezierPath(roundedRect: bgRect, xRadius: 228, yRadius: 228)

let bgGradient = NSGradient(colors: [
    NSColor(srgbRed: 0.165, green: 0.196, blue: 0.267, alpha: 1),
    NSColor(srgbRed: 0.063, green: 0.078, blue: 0.125, alpha: 1)
])!
bgGradient.draw(in: bgPath, angle: -90)

NSColor.white.withAlphaComponent(0.10).setStroke()
bgPath.lineWidth = 4
bgPath.stroke()

// ── Phone silhouette ──────────────────────────────────────────────────────
let phoneRect = NSRect(x: 300, y: 186, width: 424, height: 652)
let phone = NSBezierPath(roundedRect: phoneRect, xRadius: 84, yRadius: 84)
NSColor.white.withAlphaComponent(0.055).setFill()
phone.fill()
NSColor.white.withAlphaComponent(0.16).setStroke()
phone.lineWidth = 16
phone.stroke()

// Speaker slot
let slot = NSBezierPath(
    roundedRect: NSRect(x: 462, y: 764, width: 100, height: 20),
    xRadius: 10, yRadius: 10
)
NSColor.white.withAlphaComponent(0.20).setFill()
slot.fill()

// ── Green play button ─────────────────────────────────────────────────────
let center = NSPoint(x: 512, y: 486)
let radius: CGFloat = 196
let circleRect = NSRect(
    x: center.x - radius, y: center.y - radius,
    width: radius * 2, height: radius * 2
)
let circle = NSBezierPath(ovalIn: circleRect)

ctx.saveGState()
ctx.setShadow(
    offset: CGSize(width: 0, height: -14),
    blur: 44,
    color: NSColor(srgbRed: 0.12, green: 0.72, blue: 0.32, alpha: 0.55).cgColor
)
let greenGradient = NSGradient(colors: [
    NSColor(srgbRed: 0.235, green: 0.855, blue: 0.404, alpha: 1),
    NSColor(srgbRed: 0.106, green: 0.635, blue: 0.278, alpha: 1)
])!
greenGradient.draw(in: circle, angle: -90)
ctx.restoreGState()

// Play triangle (optically centred)
let tri = NSBezierPath()
tri.move(to: NSPoint(x: 446, y: 610))
tri.line(to: NSPoint(x: 446, y: 362))
tri.line(to: NSPoint(x: 650, y: 486))
tri.close()
NSColor.white.setFill()
tri.fill()

image.unlockFocus()

// ── Write PNG ─────────────────────────────────────────────────────────────
guard let tiff = image.tiffRepresentation,
      let rep = NSBitmapImageRep(data: tiff),
      let png = rep.representation(using: .png, properties: [:]) else {
    FileHandle.standardError.write(Data("icon: failed to encode PNG\n".utf8))
    exit(1)
}

let outDir = URL(fileURLWithPath: "Resources", isDirectory: true)
try? FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)
let master = outDir.appendingPathComponent("icon-1024.png")
try png.write(to: master)
print("wrote \(master.path)")
