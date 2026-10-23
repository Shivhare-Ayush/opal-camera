import SwiftUI

public struct FlywheelView: View {
    @Binding public var activePreset: LookPreset
    @Binding public var isPresented: Bool
    public var spawnPosition: CGPoint?
    @Binding public var hoveredPreset: LookPreset?

    // Flywheel Geometry
    private let wedgeCount = 6
    private let innerRadius: CGFloat = 45
    public static let outerRadius: CGFloat = 135

    @State private var internalHoveredPreset: LookPreset?
    @State private var lastHapticIndex: Int = -1

    private let hapticFeedback = UIImpactFeedbackGenerator(style: .medium)

    public init(
        activePreset: Binding<LookPreset>,
        isPresented: Binding<Bool>,
        spawnPosition: CGPoint? = nil,
        hoveredPreset: Binding<LookPreset?>? = nil
    ) {
        self._activePreset = activePreset
        self._isPresented = isPresented
        self.spawnPosition = spawnPosition
        self._hoveredPreset = hoveredPreset ?? .constant(nil)
    }

    /// Computes clamped center so the 135pt radial wheel never clips screen edges.
    public static func clampedCenter(spawnPosition: CGPoint?, in size: CGSize) -> CGPoint {
        let defaultCenter = CGPoint(x: size.width / 2, y: size.height / 2)
        let rawCenter = spawnPosition ?? defaultCenter
        let clampedX = min(max(rawCenter.x, outerRadius + 16), size.width - outerRadius - 16)
        let clampedY = min(max(rawCenter.y, outerRadius + 70), size.height - outerRadius - 90)
        return CGPoint(x: clampedX, y: clampedY)
    }

    private var currentHovered: LookPreset {
        hoveredPreset ?? internalHoveredPreset ?? activePreset
    }

    public var body: some View {
        GeometryReader { screenGeo in
            let center = Self.clampedCenter(spawnPosition: spawnPosition, in: screenGeo.size)

            ZStack {
                // Dimmed Viewfinder Backdrop
                Color.black.opacity(0.35)
                    .ignoresSafeArea()
                    .onTapGesture {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                            isPresented = false
                        }
                    }

                // Radial Flywheel centered at clamped touch position
                ZStack {
                    // Central Ring Hub
                    Circle()
                        .fill(.ultraThinMaterial)
                        .frame(width: innerRadius * 2, height: innerRadius * 2)
                        .overlay(
                            VStack(spacing: 2) {
                                Image(systemName: "camera.filters")
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundColor(currentHovered.accentColor)
                                Text(currentHovered.displayName)
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundColor(.white)
                                    .lineLimit(1)
                            }
                        )
                        .onTapGesture {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                isPresented = false
                            }
                        }

                    // 6 Radial Wedges
                    ForEach(LookPreset.allCases) { preset in
                        WedgeShape(
                            index: preset.id,
                            totalCount: wedgeCount,
                            innerRadius: innerRadius,
                            outerRadius: isHovered(preset) ? outerRadius + 12 : outerRadius
                        )
                        .fill(
                            isHovered(preset)
                                ? preset.accentColor.opacity(0.85)
                                : (preset == activePreset ? preset.accentColor.opacity(0.4) : Color.white.opacity(0.18))
                        )
                        .overlay(
                            WedgeShape(
                                index: preset.id,
                                totalCount: wedgeCount,
                                innerRadius: innerRadius,
                                outerRadius: isHovered(preset) ? outerRadius + 12 : outerRadius
                            )
                            .stroke(Color.white.opacity(isHovered(preset) ? 0.9 : 0.25), lineWidth: 1.5)
                        )
                        .overlay(
                            WedgeLabel(
                                preset: preset,
                                index: preset.id,
                                totalCount: wedgeCount,
                                radius: (innerRadius + outerRadius) / 2
                            )
                        )
                        .onTapGesture {
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                                activePreset = preset
                                isPresented = false
                            }
                            UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
                        }
                    }
                }
                .frame(width: outerRadius * 2.4, height: outerRadius * 2.4)
                .position(center)
            }
            // Screen-wide drag handler tracking relative to the dynamic center
            .gesture(
                DragGesture(minimumDistance: 0, coordinateSpace: .global)
                    .onChanged { value in
                        handleDrag(location: value.location, center: center)
                    }
                    .onEnded { _ in
                        handleRelease()
                    }
            )
        }
        .onAppear {
            hapticFeedback.prepare()
            internalHoveredPreset = activePreset
        }
    }

    // MARK: - Gesture Math

    private func handleDrag(location: CGPoint, center: CGPoint) {
        if let newPreset = LookPreset.preset(at: location, relativeTo: center, innerDeadZone: innerRadius * 0.5) {
            if currentHovered != newPreset {
                internalHoveredPreset = newPreset
                hoveredPreset = newPreset
                if lastHapticIndex != newPreset.id {
                    hapticFeedback.impactOccurred()
                    lastHapticIndex = newPreset.id
                }
            }
        }
    }

    private func handleRelease() {
        let selected = currentHovered
        withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
            activePreset = selected
            isPresented = false
        }
        UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
    }

    private func isHovered(_ preset: LookPreset) -> Bool {
        return currentHovered == preset
    }
}

// MARK: - Wedge Geometric Path

private struct WedgeShape: Shape {
    let index: Int
    let totalCount: Int
    let innerRadius: CGFloat
    let outerRadius: CGFloat

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let slice = (2 * Double.pi) / Double(totalCount)
        let startAngle = Angle(radians: Double(index) * slice - (Double.pi / 2) - (slice / 2))
        let endAngle = Angle(radians: Double(index + 1) * slice - (Double.pi / 2) - (slice / 2))

        path.addArc(center: center, radius: outerRadius, startAngle: startAngle, endAngle: endAngle, clockwise: false)
        path.addArc(center: center, radius: innerRadius, startAngle: endAngle, endAngle: startAngle, clockwise: true)
        path.closeSubpath()
        return path
    }
}

// MARK: - Wedge Label

private struct WedgeLabel: View {
    let preset: LookPreset
    let index: Int
    let totalCount: Int
    let radius: CGFloat

    var body: some View {
        let slice = (2 * Double.pi) / Double(totalCount)
        let midAngle = Double(index) * slice - (Double.pi / 2)
        let x = cos(midAngle) * Double(radius)
        let y = sin(midAngle) * Double(radius)

        VStack(spacing: 1) {
            Text(preset.displayName)
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(.white)
        }
        .offset(x: CGFloat(x), y: CGFloat(y))
        .allowsHitTesting(false)
    }
}
