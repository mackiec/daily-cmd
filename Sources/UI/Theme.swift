import SwiftUI

extension Color {
    init(hex: UInt32) {
        self.init(.sRGB, red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255)
    }
}

// Traditional Japanese colours, after Nuevo.Tokyo's Japanese Colours [For UI]. See ux-flows.md.
enum Theme {
    static let base = Color(hex: 0xF7F7F6)
    static let shiro = Color(hex: 0xDCDDDD)    // Shiro Nezu, white grey
    static let usukumo = Color(hex: 0xD4DCDA)  // Usukumo Nezu, light grey cloud
    static let fuji = Color(hex: 0xA6A5C4)     // Fuji Nezu, wisteria grey
    static let sakura = Color(hex: 0xEDCAD4)   // soft sakura pink
    static let yanagi = Color(hex: 0xC8D5BB)   // Yanagi Nezumi, willow grey
    static let minato = Color(hex: 0x80989B)   // Minato Nezumi
    static let sabi = Color(hex: 0x47585C)     // Sabi Nezu, rust grey: primary text
    // deeper takes on Minato and Fuji, dark enough for small text on the base (4.5:1 or more)
    static let muted = Color(hex: 0x5E7275)
    static let fujiDeep = Color(hex: 0x5F5B8C)

    // health, as muted traditional hues: willow (fine), persimmon (dropping fast), ochre (tight), akabeni red (critical)
    static let willow = Color(hex: 0x6F8F5E)
    static let persimmon = Color(hex: 0xD0804A)
    static let ochre = Color(hex: 0xC79A2E)
    static let akabeni = Color(hex: 0xC3524A)

    // the flowing header: calm when the Mac is healthy, warming as RAM gets tight
    static let calm: [Color] = [fuji, sakura, Color(hex: 0xF4EFF3), Color(hex: 0xC9C4DF), usukumo, Color(hex: 0xF2D9E0)]
    static let warm: [Color] = [Color(hex: 0xF1D3AE), sakura, Color(hex: 0xF7EDE1), Color(hex: 0xE6C29C), Color(hex: 0xF2DCCB), Color(hex: 0xDCC4D8)]
    static let hot: [Color] = [Color(hex: 0xEDB2A2), Color(hex: 0xE9C0B5), Color(hex: 0xF7E4DB), Color(hex: 0xE3A394), Color(hex: 0xF2CFC2), sakura]
    static func aura(_ h: Health) -> [Color] { h == .ok ? calm : h == .critical ? hot : warm }
}

extension View {
    // Nuevo-style caption: small, uppercase, widely spaced mono
    func monoLabel(_ size: CGFloat = 10) -> some View {
        font(.system(size: size, design: .monospaced)).tracking(1.4).textCase(.uppercase)
    }
}
