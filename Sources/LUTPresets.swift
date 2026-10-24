import Foundation
import CoreImage
import SwiftUI

// MARK: - Look Preset Identifiers

public enum LookPreset: Int, CaseIterable, Identifiable, Sendable {
    case cleanPunch = 0       // Default Launch Look (Option A)
    case rahilFilmic = 1      // Signature 35mm film emulation
    case goldenHourSkyline = 2 // Warm sunset glow + enhanced sky
    case moodyEditorial = 3   // Low-key architectural street drama
    case portra400Day = 4     // Classic daylight film emulation
    case midnightCity = 5     // Neon night grade with skin protection

    public var id: Int { rawValue }

    public var displayName: String {
        switch self {
        case .cleanPunch: return "Clean Punch"
        case .rahilFilmic: return "Rahil Filmic"
        case .goldenHourSkyline: return "Golden Hour"
        case .moodyEditorial: return "Moody Editorial"
        case .portra400Day: return "Portra 400"
        case .midnightCity: return "Midnight City"
        }
    }

    public var subtitle: String {
        switch self {
        case .cleanPunch: return "Instant Share Polish"
        case .rahilFilmic: return "35mm Analog Warmth"
        case .goldenHourSkyline: return "Cinematic Amber Sky"
        case .moodyEditorial: return "Low-Key Street Contrast"
        case .portra400Day: return "Daylight Organic Greens"
        case .midnightCity: return "Electric Neon Glow"
        }
    }

    public var accentColor: Color {
        switch self {
        case .cleanPunch: return .blue
        case .rahilFilmic: return .orange
        case .goldenHourSkyline: return .yellow
        case .moodyEditorial: return .purple
        case .portra400Day: return .green
        case .midnightCity: return .cyan
        }
    }

    /// Evaluates which radial wedge is hovered based on touch location relative to center.
    /// Maps North (270° in iOS screen coordinates) directly to Clean Punch (index 0).
    public static func preset(at location: CGPoint, relativeTo center: CGPoint, innerDeadZone: CGFloat = 22) -> LookPreset? {
        let dx = location.x - center.x
        let dy = location.y - center.y
        let distance = sqrt(dx * dx + dy * dy)
        guard distance > innerDeadZone else { return nil }

        var angle = atan2(dy, dx) * 180 / .pi
        if angle < 0 { angle += 360 }

        let wedgeCount = 6
        let sliceAngle: Double = 360.0 / Double(wedgeCount)
        let normalizedAngle = (angle + 90.0).truncatingRemainder(dividingBy: 360.0)
        let adjustedAngle = (normalizedAngle + (sliceAngle / 2.0)).truncatingRemainder(dividingBy: 360.0)
        let index = Int(adjustedAngle / sliceAngle) % wedgeCount

        return LookPreset(rawValue: index)
    }
}

// MARK: - Thread-Safe 3D Color Cube Filter Cache & Generator

public final class LUTPresets: @unchecked Sendable {
    public static let shared = LUTPresets()

    public static let cubeDimension: Int = 32
    private var prebakedCubeData: [LookPreset: Data] = [:]
    private let lock = NSLock()

    private init() {
        prebakeCubes()
    }

    /// Pre-bakes all 6 immutable 3D cube data buffers at launch.
    /// Eliminates runtime allocation latency while ensuring 100% thread safety.
    public func prebakeCubes() {
        lock.lock()
        defer { lock.unlock() }
        for preset in LookPreset.allCases {
            let data = Self.createColorCubeData(for: preset, dimension: Self.cubeDimension)
            prebakedCubeData[preset] = data
        }
    }

    /// Returns the pre-baked immutable cube data for a preset.
    public func cubeData(for preset: LookPreset) -> Data {
        lock.lock()
        defer { lock.unlock() }
        if let data = prebakedCubeData[preset] {
            return data
        }
        let freshData = Self.createColorCubeData(for: preset, dimension: Self.cubeDimension)
        prebakedCubeData[preset] = freshData
        return freshData
    }

    /// Thread-safe pure functional grading. Creates no shared mutable state.
    public func applyGrade(to image: CIImage, preset: LookPreset) -> CIImage {
        let data = cubeData(for: preset)
        return image.applyingFilter("CIColorCube", parameters: [
            "inputCubeDimension": Self.cubeDimension,
            "inputCubeData": data
        ])
    }

    /// Creates a dedicated, isolated CIFilter instance per caller when explicit filter object is needed.
    public func createFreshFilter(for preset: LookPreset) -> CIFilter? {
        let data = cubeData(for: preset)
        guard let filter = CIFilter(name: "CIColorCube") else { return nil }
        filter.setValue(Self.cubeDimension, forKey: "inputCubeDimension")
        filter.setValue(data, forKey: "inputCubeData")
        return filter
    }

    // MARK: - Color Science 3D Cube Math

    /// Procedurally builds 3D color cube data for CIColorCube adhering to "Natural Skin with Richer Scenery".
    public static func createColorCubeData(for preset: LookPreset, dimension: Int = 32) -> Data {
        let dim = max(2, min(dimension, 64)) // Bounded dimension safeguard
        let size = dim * dim * dim * 4
        var cube = [Float](repeating: 0, count: size)
        var offset = 0

        let invDim = 1.0 / Float(dim - 1)

        for bIndex in 0..<dim {
            let b = Float(bIndex) * invDim
            for gIndex in 0..<dim {
                let g = Float(gIndex) * invDim
                for rIndex in 0..<dim {
                    let r = Float(rIndex) * invDim

                    // Transform (r, g, b) according to preset color science
                    let (outR, outG, outB) = gradePixel(r: r, g: g, b: b, preset: preset)

                    cube[offset] = clamp(outR)
                    cube[offset + 1] = clamp(outG)
                    cube[offset + 2] = clamp(outB)
                    cube[offset + 3] = 1.0 // Alpha
                    offset += 4
                }
            }
        }

        return Data(bytes: cube, count: size * MemoryLayout<Float>.size)
    }

    // MARK: - Preset Math Transformations (Empirical Social Archetypes & Codex Compliant)

    private static func quinticSmoothstep(_ t: Float) -> Float {
        let tc = min(max(t, 0.0), 1.0)
        return tc * tc * tc * (tc * (tc * 6.0 - 15.0) + 10.0)
    }

    private static func c2TonalCurve(_ v: Float, lMin: Float, lMax: Float) -> Float {
        return lMin + (lMax - lMin) * quinticSmoothstep(v)
    }

    private static func rgbToHsv(r: Float, g: Float, b: Float) -> (h: Float, s: Float, v: Float) {
        let cmax = max(r, max(g, b))
        let cmin = min(r, min(g, b))
        let delta = cmax - cmin

        var h: Float = 0.0
        if delta > 1e-7 {
            if cmax == r {
                h = 60.0 * (((g - b) / delta).truncatingRemainder(dividingBy: 6.0))
            } else if cmax == g {
                h = 60.0 * (((b - r) / delta) + 2.0)
            } else {
                h = 60.0 * (((r - g) / delta) + 4.0)
            }
            if h < 0.0 { h += 360.0 }
        }

        let s = cmax > 1e-7 ? delta / cmax : 0.0
        let v = cmax
        return (h, s, v)
    }

    private static func hsvToRgb(h: Float, s: Float, v: Float) -> (r: Float, g: Float, b: Float) {
        let normH = (h.truncatingRemainder(dividingBy: 360.0) + 360.0).truncatingRemainder(dividingBy: 360.0)
        let clampedS = min(max(s, 0.0), 1.0)
        let clampedV = min(max(v, 0.0), 1.0)

        let c = clampedV * clampedS
        let x = c * (1.0 - abs(((normH / 60.0).truncatingRemainder(dividingBy: 2.0)) - 1.0))
        let m = clampedV - c

        let sector = Int(normH / 60.0) % 6
        var (rr, gg, bb): (Float, Float, Float) = (0, 0, 0)
        switch sector {
        case 0: (rr, gg, bb) = (c, x, 0)
        case 1: (rr, gg, bb) = (x, c, 0)
        case 2: (rr, gg, bb) = (0, c, x)
        case 3: (rr, gg, bb) = (0, x, c)
        case 4: (rr, gg, bb) = (x, 0, c)
        default: (rr, gg, bb) = (c, 0, x)
        }
        return (clamp(rr + m), clamp(gg + m), clamp(bb + m))
    }

    private static func computeMelaninWeight(h: Float, lum: Float) -> Float {
        let hCenter: Float = 27.5
        let hRadius: Float = 17.5
        let hDist = abs(h - hCenter)
        let wHue: Float = hDist < hRadius ? pow(cos((Float.pi / 2.0) * (hDist / hRadius)), 2) : 0.0

        var wLum: Float = 0.0
        if lum >= 0.2 && lum <= 0.8 {
            wLum = 1.0
        } else if lum >= 0.05 && lum < 0.2 {
            wLum = pow(sin((Float.pi / 2.0) * ((lum - 0.05) / 0.15)), 2)
        } else if lum > 0.8 && lum <= 0.95 {
            wLum = pow(cos((Float.pi / 2.0) * ((lum - 0.8) / 0.15)), 2)
        }
        return wHue * wLum
    }

    private static func gradePixel(r: Float, g: Float, b: Float, preset: LookPreset) -> (Float, Float, Float) {
        // Luminance calculation (Rec. 709)
        let lum = 0.2126 * r + 0.7152 * g + 0.0722 * b

        // 1. Convert to HSV
        let (h, s, v) = rgbToHsv(r: r, g: g, b: b)

        // 2. Melanin Sanctuary Weight (Fitzpatrick I-VI midtone corridor)
        let wSkin = computeMelaninWeight(h: h, lum: lum)

        var lMin: Float = 0.0
        var lMax: Float = 1.0
        var envRotations: [(low: Float, high: Float, delta: Float)] = []
        var satBg: Float = 0.0
        var satSkinCap: Float = 0.04
        var hltWarmthDrb: Float = 0.0
        var shdWarmthDrb: Float = 0.0

        switch preset {
        case .cleanPunch:
            // Daytime City: Deep cobalt polarized sky (-10°), crisp contrast
            lMin = 0.050; lMax = 0.960
            envRotations = [(190.0, 240.0, -10.0)]
            satBg = 0.15; satSkinCap = 0.04

        case .rahilFilmic:
            // Street & Flash Editorial: Lifted matte black floor, soft highlight shoulder, Kodak daylight warmth
            lMin = 0.133; lMax = 0.925
            satBg = 0.08; satSkinCap = 0.03
            hltWarmthDrb = 0.165
            shdWarmthDrb = 0.060

        case .goldenHourSkyline:
            // Sunset / Rooftop: Specular sunset warmth, melanin saturation locked (+4% max)
            lMin = 0.070; lMax = 0.949
            envRotations = [(20.0, 60.0, 12.0)]
            satBg = 0.18; satSkinCap = 0.04
            hltWarmthDrb = 0.180

        case .midnightCity:
            // Night City Neon: Sodium lamps shifted toward amber (-13°), cool indigo shadows
            lMin = 0.086; lMax = 0.960
            envRotations = [(50.0, 75.0, -13.0)]
            satBg = 0.15; satSkinCap = 0.02
            shdWarmthDrb = -0.080

        case .portra400Day:
            // Nature & Foliage: Digital green -> olive/sage (-15°), aquatic cyan deepening
            lMin = 0.078; lMax = 0.972
            envRotations = [(105.0, 145.0, -15.0), (175.0, 205.0, -8.0)]
            satBg = 0.12; satSkinCap = 0.04
            hltWarmthDrb = 0.080

        case .moodyEditorial:
            // Indoor Cafe & Dining: Clean white tableware anchor, cozy ambient shadow warmth
            lMin = 0.070; lMax = 0.941
            envRotations = [(35.0, 65.0, 6.0)]
            satBg = 0.10; satSkinCap = 0.03
            shdWarmthDrb = 0.050
        }

        // 3. Tonal curve applied to V (C2 continuous quintic Hermite)
        let vNew = c2TonalCurve(v, lMin: lMin, lMax: lMax)

        // 4. Environmental Hue Rotations with zero skin hue shift
        var hNew = h
        for rot in envRotations {
            let center = (rot.low + rot.high) / 2.0
            let halfWidth = (rot.high - rot.low) / 2.0
            let directDist = abs(h - center)
            let circDist = min(directDist, 360.0 - directDist)
            if circDist < halfWidth {
                let mask = pow(cos((Float.pi / 2.0) * (circDist / halfWidth)), 2)
                let effectiveWeight = mask * (1.0 - wSkin)
                hNew = (hNew + effectiveWeight * rot.delta).truncatingRemainder(dividingBy: 360.0)
                if hNew < 0 { hNew += 360.0 }
            }
        }

        // 5. Selective Saturation Modulation
        let effectiveSatBoost = (1.0 - wSkin) * satBg + wSkin * satSkinCap
        let sNew = min(max(s * (1.0 + effectiveSatBoost), 0.0), 1.0)

        // 6. Convert back to RGB
        var (outR, outG, outB) = hsvToRgb(h: hNew, s: sNew, v: vNew)

        // 7. Luminance-Neutral Chrominance Split-Toning (Rec. 709)
        if hltWarmthDrb != 0.0 {
            let hltIn = min(max((lum - 0.55) / 0.45, 0.0), 1.0)
            let hltWeight = quinticSmoothstep(hltIn) * (1.0 - v)
            let dr = hltWeight * (hltWarmthDrb * 0.35)
            let dg = -0.1963087 * dr
            let db = -dr
            outR += dr; outG += dg; outB += db
        }

        if shdWarmthDrb != 0.0 {
            let shdIn = min(max((0.45 - lum) / 0.45, 0.0), 1.0)
            let shdWeight = quinticSmoothstep(shdIn) * v
            let dr = shdWeight * (shdWarmthDrb * 0.35)
            let dg = -0.1963087 * dr
            let db = -dr
            outR += dr; outG += dg; outB += db
        }

        return (clamp(outR), clamp(outG), clamp(outB))
    }

    private static func mix(_ a: Float, _ b: Float, _ t: Float) -> Float {
        return a * (1.0 - t) + b * t
    }

    private static func clamp(_ val: Float) -> Float {
        return min(max(val, 0.0), 1.0)
    }
}
