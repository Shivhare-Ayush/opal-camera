import SwiftUI
import MetalKit
import CoreImage

public enum OpalMode: String, CaseIterable {
    case camera = "CAMERA"
    case library = "LIBRARY"
}

public struct CameraViewfinder: View {
    @StateObject private var camera = CameraSessionManager.shared
    @StateObject private var albumManager = AlbumManager.shared
    @State private var currentMode: OpalMode = .camera
    @State private var showFlywheel: Bool = false
    @State private var flywheelSpawnPoint: CGPoint? = nil
    @State private var flywheelHoveredPreset: LookPreset? = nil
    @State private var holdTask: Task<Void, Never>? = nil
    @State private var isHoldGestureActive: Bool = false
    @State private var currentFrame: CIImage?
    @State private var showingCleanupAlert: Bool = false
    @State private var cleanupResultMessage: String = ""

    public init() {}

    public var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 0) {
                // Top Header (Brand + Mode Pill Switcher + Test Cleanup)
                HStack {
                    Text("OPAL")
                        .font(.system(size: 11, weight: .black))
                        .tracking(3)
                        .foregroundColor(.white.opacity(0.85))

                    Spacer()

                    // Mode Toggle Capsule
                    HStack(spacing: 2) {
                        Button(action: {
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                                currentMode = .camera
                            }
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        }) {
                            HStack(spacing: 4) {
                                Image(systemName: "camera.fill")
                                    .font(.system(size: 10))
                                Text("CAM")
                                    .font(.system(size: 10, weight: .bold))
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(currentMode == .camera ? Color.white.opacity(0.25) : Color.clear)
                            .foregroundColor(.white)
                            .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)

                        Button(action: {
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                                currentMode = .library
                            }
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        }) {
                            HStack(spacing: 4) {
                                Image(systemName: "photo.stack.fill")
                                    .font(.system(size: 10))
                                Text("PHOTOS")
                                    .font(.system(size: 10, weight: .bold))
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(currentMode == .library ? Color.white.opacity(0.25) : Color.clear)
                            .foregroundColor(.white)
                            .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(2)
                    .background(.ultraThinMaterial)
                    .clipShape(Capsule())
                    .overlay(Capsule().stroke(Color.white.opacity(0.15), lineWidth: 1))

                    Spacer()

                    // One-Tap Album Test Cleanup
                    Button(action: { showingCleanupAlert = true }) {
                        Image(systemName: "trash.circle")
                            .font(.system(size: 20))
                            .foregroundColor(.white.opacity(0.7))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .padding(.bottom, 8)

                // Main Content Body (Camera Viewfinder vs Photo Library Grading)
                if currentMode == .camera {
                    cameraViewportView
                } else {
                    PhotoGradingView(
                        camera: camera,
                        albumManager: albumManager,
                        showFlywheel: $showFlywheel,
                        flywheelSpawnPoint: $flywheelSpawnPoint,
                        flywheelHoveredPreset: $flywheelHoveredPreset
                    )
                    .transition(.opacity)
                }
            }

            // Radial Flywheel Layer (Overlaid dynamically when triggered in either mode)
            if showFlywheel {
                FlywheelView(
                    activePreset: $camera.activePreset,
                    isPresented: $showFlywheel,
                    spawnPosition: flywheelSpawnPoint,
                    hoveredPreset: $flywheelHoveredPreset
                )
                .transition(.opacity.combined(with: .scale(scale: 0.85)))
                .zIndex(10)
            }
        }
        .onAppear {
            camera.onFrameProcessed = { frame in
                self.currentFrame = frame
            }
            Task {
                if await camera.checkCameraPermissions() {
                    camera.configureSession()
                }
                await albumManager.checkAuthorization()
            }
        }
        .alert("Clean Up Test Album?", isPresented: $showingCleanupAlert) {
            Button("Delete All LiveGraded Photos", role: .destructive) {
                albumManager.cleanupTestAlbum { result in
                    switch result {
                    case .success(let count):
                        cleanupResultMessage = "Deleted \(count) test photos."
                    case .failure(let err):
                        cleanupResultMessage = "Error: \(err.localizedDescription)"
                    }
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will wipe only photos saved in the 'LiveGraded Photos' album for quick testing resets.")
        }
    }

    // MARK: - Camera Viewport & Controls Subview

    private var cameraViewportView: some View {
        VStack(spacing: 0) {
            // Live Graded 60fps Metal Viewfinder (90% Screen)
            GeometryReader { geo in
                ZStack {
                    MetalViewRepresentable(image: currentFrame)
                        .frame(width: geo.size.width, height: geo.size.height)
                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .stroke(Color.white.opacity(0.15), lineWidth: 1)
                        )
                }
                // Hold-and-drag to spawn Flywheel anywhere on camera viewfinder
                .gesture(
                    DragGesture(minimumDistance: 0, coordinateSpace: .global)
                        .onChanged { value in
                            handleViewportDragChanged(value: value)
                        }
                        .onEnded { value in
                            handleViewportDragEnded(value: value)
                        }
                )
            }
            .padding(.horizontal, 10)

            // Bottom Control Deck (Look Switcher Pill above, Controls Row below)
            VStack(spacing: 14) {
                // Look Switcher Pill (Clear, generous, centered tap target)
                Button(action: {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                        flywheelSpawnPoint = nil
                        flywheelHoveredPreset = camera.activePreset
                        showFlywheel.toggle()
                    }
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                }) {
                    HStack(spacing: 8) {
                        Circle()
                            .fill(camera.activePreset.accentColor)
                            .frame(width: 9, height: 9)

                        Text(camera.activePreset.displayName)
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(.white)

                        Image(systemName: "chevron.up.circle.fill")
                            .font(.system(size: 14))
                            .foregroundColor(.white.opacity(0.6))
                    }
                    .padding(.horizontal, 22)
                    .padding(.vertical, 10)
                    .background(.ultraThinMaterial)
                    .clipShape(Capsule())
                    .overlay(Capsule().stroke(Color.white.opacity(0.25), lineWidth: 1.5))
                    .shadow(color: .black.opacity(0.4), radius: 8, y: 4)
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)

                // Main Shutter & Inspect Row
                HStack {
                    // Bottom-Left Inspect / Library Button
                    Button(action: {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                            currentMode = .library
                        }
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    }) {
                        ZStack {
                            if let thumb = camera.lastCapturedThumbnail {
                                Image(uiImage: thumb)
                                    .resizable()
                                    .aspectRatio(contentMode: .fill)
                                    .frame(width: 52, height: 52)
                                    .clipShape(Circle())
                                    .overlay(Circle().stroke(Color.white, lineWidth: 2))
                            } else {
                                Circle()
                                    .fill(Color.white.opacity(0.18))
                                    .frame(width: 52, height: 52)
                                    .overlay(
                                        Image(systemName: "photo.stack")
                                            .font(.system(size: 20))
                                            .foregroundColor(.white)
                                    )
                            }
                        }
                        .frame(width: 52, height: 52)
                        .contentShape(Circle())
                    }
                    .buttonStyle(.plain)

                    Spacer()

                    // Shutter Button
                    Button(action: {
                        camera.capturePhoto()
                    }) {
                        ZStack {
                            Circle()
                                .stroke(Color.white, lineWidth: 4)
                                .frame(width: 74, height: 74)
                            Circle()
                                .fill(Color.white)
                                .frame(width: 62, height: 62)
                        }
                        .contentShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .disabled(camera.isCapturing)

                    Spacer()

                    // Empty anchor to balance HStack
                    Color.clear.frame(width: 52, height: 52)
                }
                .padding(.horizontal, 28)
                .padding(.bottom, 22)
            }
        }
    }

    // MARK: - Hold-and-Drag Flywheel Gestures

    private func handleViewportDragChanged(value: DragGesture.Value) {
        let distance = hypot(value.translation.width, value.translation.height)

        if !isHoldGestureActive {
            isHoldGestureActive = true
            flywheelSpawnPoint = value.startLocation
            flywheelHoveredPreset = camera.activePreset

            // 160ms hold timer for static finger press
            holdTask?.cancel()
            holdTask = Task { @MainActor in
                try? await Task.sleep(nanoseconds: 160_000_000)
                if isHoldGestureActive && !showFlywheel {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                        showFlywheel = true
                    }
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                }
            }
        }

        // If user drags > 12pt, spawn immediately without waiting for timer
        if distance > 12 && !showFlywheel {
            holdTask?.cancel()
            withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                showFlywheel = true
            }
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        }

        // Update hovered preset as user drags outward
        if showFlywheel {
            let center = FlywheelView.clampedCenter(
                spawnPosition: flywheelSpawnPoint ?? value.startLocation,
                in: UIScreen.main.bounds.size
            )
            if let preset = LookPreset.preset(at: value.location, relativeTo: center) {
                if flywheelHoveredPreset != preset {
                    flywheelHoveredPreset = preset
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                }
            }
        }
    }

    private func handleViewportDragEnded(value: DragGesture.Value) {
        holdTask?.cancel()
        isHoldGestureActive = false

        if showFlywheel {
            if let selected = flywheelHoveredPreset {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                    camera.activePreset = selected
                    showFlywheel = false
                }
                UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
            } else {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                    showFlywheel = false
                }
            }
        }
    }
}

// MARK: - Metal Viewport Representable

public struct MetalViewRepresentable: UIViewRepresentable {
    let image: CIImage?

    public func makeUIView(context: Context) -> MTKView {
        let view = MTKView()
        view.device = MTLCreateSystemDefaultDevice()
        view.isPaused = false
        view.enableSetNeedsDisplay = false
        view.framebufferOnly = false
        view.delegate = context.coordinator
        view.clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
        return view
    }

    public func updateUIView(_ uiView: MTKView, context: Context) {
        context.coordinator.currentImage = image
    }

    public func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    public class Coordinator: NSObject, MTKViewDelegate {
        var currentImage: CIImage?
        private let context: CIContext?
        private let commandQueue: MTLCommandQueue?

        override init() {
            guard let device = MTLCreateSystemDefaultDevice() else {
                self.context = nil
                self.commandQueue = nil
                super.init()
                return
            }
            self.context = CIContext(mtlDevice: device)
            self.commandQueue = device.makeCommandQueue()
            super.init()
        }

        public func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

        public func draw(in view: MTKView) {
            guard let currentImage = currentImage,
                  let currentDrawable = view.currentDrawable,
                  let commandQueue = commandQueue,
                  let context = context else { return }

            guard let commandBuffer = commandQueue.makeCommandBuffer() else { return }

            let destination = CIRenderDestination(
                width: Int(view.drawableSize.width),
                height: Int(view.drawableSize.height),
                pixelFormat: view.colorPixelFormat,
                commandBuffer: commandBuffer,
                mtlTextureProvider: { currentDrawable.texture }
            )

            // Aspect Fill Scaled Image
            let scaleX = view.drawableSize.width / currentImage.extent.width
            let scaleY = view.drawableSize.height / currentImage.extent.height
            let scale = max(scaleX, scaleY)
            let scaledImage = currentImage.transformed(by: CGAffineTransform(scaleX: scale, y: scale))

            _ = try? context.startTask(toRender: scaledImage, to: destination)

            commandBuffer.present(currentDrawable)
            commandBuffer.commit()
        }
    }
}
