import SwiftUI

// The flowing header: a 3×3 mesh gradient whose inner points drift and whose colours
// slowly cross-fade through the palette. Each point moves on its own slow sine waves,
// so the shape never quite repeats. A new seed on every open gives a fresh configuration.
struct Aura: View {
    let palette: [Color]
    let running: Bool
    let seed: Double

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 20, paused: !running)) { ctx in
            let t = ctx.date.timeIntervalSinceReferenceDate + seed
            MeshGradient(width: 3, height: 3, points: Aura.points(t), colors: Aura.colors(t, palette), smoothsColors: true)
        }
    }

    private static func wave(_ t: Double, _ speed: Double, _ phase: Double) -> Float {
        Float(sin(t * speed + phase))
    }

    // Corners stay pinned; edge points slide along their edge; the centre wanders freely.
    static func points(_ t: Double) -> [SIMD2<Float>] {
        let a: Float = 0.2
        return [
            [0, 0], [0.5 + a * wave(t, 0.19, 1), 0], [1, 0],
            [0, 0.5 + a * wave(t, 0.23, 2)],
            [0.5 + 1.5 * a * wave(t, 0.17, 3), 0.5 + 1.5 * a * wave(t, 0.29, 4)],
            [1, 0.5 + a * wave(t, 0.21, 5)],
            [0, 1], [0.5 + a * wave(t, 0.25, 6), 1], [1, 1],
        ]
    }

    // Every point walks through the palette at its own pace, easing between neighbours.
    static func colors(_ t: Double, _ palette: [Color]) -> [Color] {
        let n = palette.count
        return (0..<9).map { i in
            let u = (t * (0.06 + 0.011 * Double(i)) + Double(i) * 1.37).truncatingRemainder(dividingBy: Double(n))
            let k = Int(u), f = u - Double(k)
            return palette[k].mix(with: palette[(k + 1) % n], by: f * f * (3 - 2 * f))
        }
    }
}
