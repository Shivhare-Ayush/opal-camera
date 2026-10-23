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
                        showFlywheel: $showFlywheel
                    )
                    .transition(.opacity)
                }
            }
            // Swipe right or left outside camera area to switch modes
            .gesture(
                DragGesture(minimumDistance: 45)
                    .onEnded { value in
                        if value.translation.width > 60 {
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                                currentMode = (currentMode == .camera) ? .library : .camera
                            }
                            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                        } else if value.translation.width < -60 {
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                                currentMode = (currentMode == .camera) ? .library : .camera
                            }
                            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                        }
                    }
            )

            // Radial Flywheel Layer (Overlaid when Island is active in either mode)
            if showFlywheel {
                FlywheelView(
                    activePreset: $camera.activePreset,
                    isPresented: $showFlywheel
                )
                .transition(.opacity.combined(with: .scale(scale: 0.85)))
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
            }
            .padding(.horizontal, 10)

            // Bottom Control Deck (Thumbnail/Library Link + Floating Island + Shutter)
            ZStack {
                HStack {
                    // Thumbnail Preview (Tapping jumps directly to Library mode)
                    Button(action: {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                            currentMode = .library
                        }
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    }) {
                        if let thumb = camera.lastCapturedThumbnail {
                            Image(uiImage: thumb)
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                .frame(width: 48, height: 48)
                                .clipShape(Circle())
                                .overlay(Circle().stroke(Color.white, lineWidth: 2))
                        } else {
                            Circle()
                                .fill(Color.white.opacity(0.1))
                                .frame(width: 48, height: 48)
                                .overlay(
                                    Image(systemName: "photo.stack")
                                        .font(.system(size: 18))
                                        .foregroundColor(.white.opacity(0.6))
                                )
                        }
                    }

                    Spacer()

                    // Shutter Button
                    Button(action: {
                        camera.capturePhoto()
                    }) {
                        ZStack {
                            Circle()
                                .stroke(Color.white, lineWidth: 4)
                                .frame(width: 72, height: 72)
                            Circle()
                                .fill(Color.white)
                                .frame(width: 60, height: 60)
                        }
                    }
                    .disabled(camera.isCapturing)

                    Spacer()

                    // Empty anchor to balance HStack
                    Color.clear.frame(width: 48, height: 48)
                }
                .padding(.horizontal, 28)
                .padding(.bottom, 24)
                .padding(.top, 14)

                // Floating Island (Above Shutter)
                VStack {
                    Button(action: {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                            showFlywheel.toggle()
                        }
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    }) {
                        HStack(spacing: 8) {
                            Circle()
                                .fill(camera.activePreset.accentColor)
                                .frame(width: 8, height: 8)

                            Text(camera.activePreset.displayName)
                                .font(.system(size: 13, weight: .bold))
                                .foregroundColor(.white)

                            Image(systemName: "chevron.up.circle.fill")
                                .font(.system(size: 13))
                                .foregroundColor(.white.opacity(0.6))
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(.ultraThinMaterial)
                        .clipShape(Capsule())
                        .overlay(Capsule().stroke(Color.white.opacity(0.2), lineWidth: 1))
                        .shadow(color: .black.opacity(0.3), radius: 8, y: 4)
                    }
                    .offset(y: -54)
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
