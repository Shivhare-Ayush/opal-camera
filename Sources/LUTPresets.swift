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

    // MARK: - Preset Math Transformations

    private static func gradePixel(r: Float, g: Float, b: Float, preset: LookPreset) -> (Float, Float, Float) {
        // Luminance calculation (Rec. 709)
        let lum = 0.2126 * r + 0.7152 * g + 0.0722 * b

        // Skin Tone Sanctuary: Check if color lies within melanin hue angle corridor (orange-yellow, r > g > b)
        let isSkinTone = (r > g) && (g > b) && ((r - b) > 0.1) && (r < 0.95)
        let skinWeight: Float = isSkinTone ? 0.85 : 0.0 // 85% protection if skin

        var (nr, ng, nb) = (r, g, b)

        switch preset {
        case .cleanPunch:
            // S-curve contrast + 10% micro-contrast boost on background, skin protected
            let contrast: Float = 1.10
            let rC = (r - 0.5) * contrast + 0.5
            let gC = (g - 0.5) * contrast + 0.5
            let bC = (b - 0.5) * contrast + 0.5
            let cyanBoost: Float = lum > 0.6 ? 0.04 : 0.0
            nr = mix(rC, r, skinWeight)
            ng = mix(gC + (cyanBoost * 0.5), g, skinWeight)
            nb = mix(bC + cyanBoost, b, skinWeight)

        case .rahilFilmic:
            // 35mm Analog: lifted matte black (0.04), soft analog highlight knee, muted midtone saturation
            let liftedR = r * 0.92 + 0.04
            let liftedG = g * 0.92 + 0.035
            let liftedB = b * 0.90 + 0.05 // subtle cool shadow lift
            let warmHighlight: Float = lum > 0.7 ? 0.03 : 0.0
            nr = mix(liftedR + warmHighlight, r * 0.96 + 0.02, skinWeight)
            ng = mix(liftedG, g * 0.96 + 0.02, skinWeight)
            nb = mix(liftedB, b * 0.95, skinWeight)

        case .goldenHourSkyline:
            // Warm +5° hue shift in midtones, sky saturation +25%, shadow lift +15%
            let warmR = r * 1.15 + (lum * 0.05)
            let warmG = g * 1.05
            let skyB = b > 0.4 ? (b * 1.25) : (b * 0.95) // enhance sky, warm ground
            let shadowLift: Float = lum < 0.3 ? 0.06 : 0.0
            nr = mix(warmR + shadowLift, r * 1.03, skinWeight) // skin stays natural
            ng = mix(warmG + shadowLift, g, skinWeight)
            nb = mix(skyB + (shadowLift * 0.5), b, skinWeight)

        case .moodyEditorial:
            // Low-key architectural contrast, deepened cyans, lifted blacks
            let darkR = (r - 0.5) * 1.20 + 0.5
            let darkG = (g - 0.5) * 1.15 + 0.5
            let darkB = (b - 0.5) * 1.25 + 0.5 + 0.04 // deep cyan shadows
            nr = mix(darkR, r, skinWeight)
            ng = mix(darkG, g, skinWeight)
            nb = mix(darkB, b, skinWeight)

        case .portra400Day:
            // Kodak Portra characteristic curves: warm organic skin, earthy foliage, soft knee
            let pR = r * 1.06 + (lum > 0.5 ? 0.02 : 0.0)
            let pG = g * 1.02
            let pB = b * 0.96
            nr = mix(pR, r * 1.02, skinWeight)
            ng = mix(pG, g * 1.01, skinWeight)
            nb = mix(pB, b * 0.99, skinWeight)

        case .midnightCity:
            // Neon night: boosted teal/magenta ambient curves, shadows +20%, strict skin isolation
            let neonR = (r > 0.5) ? (r * 1.2) : (r * 0.9)
            let neonG = g * 0.95
            let neonB = (b < 0.5) ? (b * 1.30) : (b * 1.15) // strong teal in shadows
            nr = mix(neonR, r, skinWeight)
            ng = mix(neonG, g, skinWeight)
            nb = mix(neonB, b, skinWeight)
        }

        return (nr, ng, nb)
    }

    private static func mix(_ a: Float, _ b: Float, _ t: Float) -> Float {
        return a * (1.0 - t) + b * t
    }

    private static func clamp(_ val: Float) -> Float {
        return min(max(val, 0.0), 1.0)
    }
}
