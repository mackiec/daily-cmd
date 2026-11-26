import SwiftUI
import AppKit

// The menu bar label: the sun, then free RAM
struct MenuBarMark: View {
    @ObservedObject var mon: Monitor
    var body: some View {
        HStack(spacing: 0) {
            Image(nsImage: Sun.image(mon.health))
            Text("\(mon.free)%")
        }
    }
}

// The menu bar mark: a sun rising over a horizon. A half disc rests on a thin line, with five rays fanned
// over the top. Wisteria at the ray tips to sakura at the horizon while the Mac is healthy, warming to
// amber when RAM is tight or dropping fast, and red when it's critical.
// It doesn't animate: a slow colour drift was tried and measured, and every update makes SwiftUI rebuild
// the menu bar item, which more than doubled cmd's idle CPU (0.50% → 1.13% of a core).
// Drawn in code (crisp at any scale) and kept in colour, so it isn't turned into a template image.
enum Sun {
    private static var cache: [Health: NSImage] = [:]

    static func image(_ h: Health) -> NSImage {
        if let i = cache[h] { return i }
        let (top, bottom): (UInt32, UInt32) = switch h {
        case .ok: (0x8C88C4, 0xF2A9BC)             // wisteria at the ray tips → sakura at the horizon
        case .falling, .tight: (0xE48A5C, 0xF6C77E) // persimmon → amber
        case .critical: (0xC3524A, 0xF2907E)       // akabeni red → coral
        }
        let i = make(NSColor(hex: top), NSColor(hex: bottom))
        cache[h] = i
        return i
    }

    // Sized from the menu bar font, so the mark stands as tall as the digits beside it: their cap height,
    // plus 8% because the rounded ray tips look shorter than flat-topped digits at the same height.
    // The menu bar draws its text a little above the middle of the item, so the mark's band sits 0.9pt
    // above the middle of its canvas to share the digits' top and bottom (measured from a capture).
    // Showing only the top half lets the disc and rays be twice the size of a whole sun at this height.
    private static let side = NSFont.menuBarFont(ofSize: 0).capHeight * 1.08
    private static let lift: CGFloat = 0.9
    private static let ray: CGFloat = 1.2       // ray stroke
    private static let horizon: CGFloat = 1.1   // horizon stroke
    // lifts the horizon onto a pixel boundary, so its lower edge lands on the digits' baseline instead of
    // smearing one pixel below it (measured from a capture)
    private static let snap: CGFloat = 0.25
    // distance from the sun's centre (on the horizon) to the middle of a ray's rounded tip
    private static let tip = side - horizon / 2 - ray / 2 - snap
    // clear space between the sun and the digits (inside the image, because the menu bar label doesn't
    // reliably honour SwiftUI spacing)
    private static let gap: CGFloat = 3

    private static func make(_ top: NSColor, _ bottom: NSColor) -> NSImage {
        let width = 2 * tip * 0.98 + horizon
        let img = NSImage(size: NSSize(width: width + gap, height: side + 2 * lift), flipped: false) { r in
            let c = NSPoint(x: width / 2, y: 2 * lift + horizon / 2 + snap)   // centre of the sun, on the horizon
            let start = tip * 0.68, disc = tip * 0.5
            // a colour from the vertical gradient: `top` at the ray tips, `bottom` at the horizon
            func shade(_ y: CGFloat) -> NSColor {
                top.blended(withFraction: 1 - min(1, max(0, (y - c.y) / tip)), of: bottom) ?? top
            }

            for deg in stride(from: 30.0, through: 150.0, by: 30.0) {
                let a = deg * .pi / 180, (ux, uy) = (cos(a), sin(a))
                let p = NSBezierPath()
                p.move(to: NSPoint(x: c.x + start * ux, y: c.y + start * uy))
                p.line(to: NSPoint(x: c.x + tip * ux, y: c.y + tip * uy))
                p.lineWidth = ray
                p.lineCapStyle = .round
                shade(c.y + (start + tip) / 2 * uy).setStroke()
                p.stroke()
            }

            let half = NSBezierPath()
            half.appendArc(withCenter: c, radius: disc, startAngle: 0, endAngle: 180)
            half.close()
            NSGradient(starting: shade(c.y + disc), ending: bottom)?.draw(in: half, angle: -90)

            let line = NSBezierPath()
            line.move(to: NSPoint(x: horizon / 2, y: c.y))
            line.line(to: NSPoint(x: width - horizon / 2, y: c.y))
            line.lineWidth = horizon
            line.lineCapStyle = .round
            bottom.setStroke()
            line.stroke()
            return true
        }
        img.isTemplate = false
        return img
    }
}

extension NSColor {
    convenience init(hex: UInt32) {
        self.init(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
                  blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
    }
}
