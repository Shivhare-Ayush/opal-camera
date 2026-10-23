import SwiftUI

public struct FlywheelView: View {
    @Binding public var activePreset: LookPreset
    @Binding public var isPresented: Bool

    // Flywheel Geometry
    private let wedgeCount = 6
    private let innerRadius: CGFloat = 45
    private let outerRadius: CGFloat = 135

    @State private var dragAngle: Double = 0
    @State private var currentHoveredPreset: LookPreset?
    @State private var lastHapticIndex: Int = -1

    private let hapticFeedback = UIImpactFeedbackGenerator(style: .medium)

    public init(activePreset: Binding<LookPreset>, isPresented: Binding<Bool>) {
        self._activePreset = activePreset
        self._isPresented = isPresented
    }

    public var body: some View {
        ZStack {
            // Dimmed Viewfinder Backdrop
            Color.black.opacity(0.35)
                .ignoresSafeArea()
                .onTapGesture {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        isPresented = false
                    }
                }

            // Radial Flywheel
            ZStack {
                // Central Ring Hub
                Circle()
                    .fill(.ultraThinMaterial)
                    .frame(width: innerRadius * 2, height: innerRadius * 2)
                    .overlay(
                        VStack(spacing: 2) {
                            Image(systemName: "camera.filters")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(currentHoveredPreset?.accentColor ?? activePreset.accentColor)
                            Text((currentHoveredPreset ?? activePreset).displayName)
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
            .gesture(
                DragGesture(minimumDistance: 10)
                    .onChanged { value in
                        handleDrag(location: value.location)
                    }
                    .onEnded { _ in
                        handleRelease()
                    }
            )
        }
        .onAppear {
            hapticFeedback.prepare()
            currentHoveredPreset = activePreset
        }
    }

    // MARK: - Gesture Math

    private func handleDrag(location: CGPoint) {
        let center = CGPoint(x: outerRadius * 1.2, y: outerRadius * 1.2)
        let dx = location.x - center.x
        let dy = location.y - center.y
        let distance = sqrt(dx * dx + dy * dy)

        guard distance > (innerRadius * 0.6) else { return }

        // Calculate Angle in Degrees (0 to 360)
        var angle = atan2(dy, dx) * 180 / .pi
        if angle < 0 { angle += 360 }

        // 6 Wedges: 60 degrees each.
        // In screen coordinates: North is 270 degrees.
        // Adding 90 degrees rotates coordinates so North (270°) maps to 0° (Clean Punch).
        let sliceAngle: Double = 360.0 / Double(wedgeCount)
        let normalizedAngle = (angle + 90.0).truncatingRemainder(dividingBy: 360.0)
        let adjustedAngle = (normalizedAngle + (sliceAngle / 2.0)).truncatingRemainder(dividingBy: 360.0)
        let index = Int(adjustedAngle / sliceAngle) % wedgeCount

        if let newPreset = LookPreset(rawValue: index) {
            if currentHoveredPreset != newPreset {
                currentHoveredPreset = newPreset
                // Trigger tactile haptic on wedge snap
                if lastHapticIndex != index {
                    hapticFeedback.impactOccurred()
                    lastHapticIndex = index
                }
            }
        }
    }

    private func handleRelease() {
        if let selected = currentHoveredPreset {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                activePreset = selected
                isPresented = false
            }
            UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
        }
    }

    private func isHovered(_ preset: LookPreset) -> Bool {
        return (currentHoveredPreset ?? activePreset) == preset
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
