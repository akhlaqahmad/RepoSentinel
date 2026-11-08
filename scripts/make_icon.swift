// Renders the app icon: swift scripts/make_icon.swift <out.iconset>
import AppKit
let out = CommandLine.arguments[1]
try? FileManager.default.createDirectory(atPath: out, withIntermediateDirectories: true)
func render(_ px: Int) -> Data {
    let img = NSImage(size: NSSize(width: px, height: px), flipped: false) { r in
        let s = CGFloat(px), inset = s * 0.08
        let body = NSBezierPath(roundedRect: r.insetBy(dx: inset, dy: inset), xRadius: s * 0.2, yRadius: s * 0.2)
        NSGradient(colors: [NSColor(red: 0.10, green: 0.45, blue: 0.95, alpha: 1), NSColor(red: 0.30, green: 0.15, blue: 0.75, alpha: 1)])!.draw(in: body, angle: -60)
        let cfg = NSImage.SymbolConfiguration(pointSize: s * 0.5, weight: .semibold).applying(.init(paletteColors: [.white]))
        if let sym = NSImage(systemSymbolName: "checkmark.shield.fill", accessibilityDescription: nil)?.withSymbolConfiguration(cfg) {
            let sz = sym.size; sym.draw(in: NSRect(x: (s - sz.width) / 2, y: (s - sz.height) / 2, width: sz.width, height: sz.height))
        }
        return true
    }
    let rep = NSBitmapImageRep(data: img.tiffRepresentation!)!
    return rep.representation(using: .png, properties: [:])!
}
for (name, px) in [("16", 16), ("16@2x", 32), ("32", 32), ("32@2x", 64), ("128", 128), ("128@2x", 256), ("256", 256), ("256@2x", 512), ("512", 512), ("512@2x", 1024)] {
    try! render(px).write(to: URL(fileURLWithPath: "\(out)/icon_\(name.replacingOccurrences(of: "@2x", with: "x2"))_tmp.png"))
    let final = name.contains("@2x") ? "icon_\(name.replacingOccurrences(of: "@2x", with: ""))x\(name.replacingOccurrences(of: "@2x", with: ""))@2x.png" : "icon_\(name)x\(name).png"
    try? FileManager.default.removeItem(atPath: "\(out)/\(final)")
    try! FileManager.default.moveItem(atPath: "\(out)/icon_\(name.replacingOccurrences(of: "@2x", with: "x2"))_tmp.png", toPath: "\(out)/\(final)")
}
