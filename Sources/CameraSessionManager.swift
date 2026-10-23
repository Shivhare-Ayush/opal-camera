import AVFoundation
import CoreImage
import SwiftUI
import MetalKit

@MainActor
public final class CameraSessionManager: NSObject, ObservableObject {
    public static let shared = CameraSessionManager()

    // Published State
    @Published public var activePreset: LookPreset = .cleanPunch {
        didSet {
            stateLock.lock()
            _safePreset = activePreset
            stateLock.unlock()
        }
    }
    @Published public var isSessionRunning: Bool = false
    @Published public var isCapturing: Bool = false
    @Published public var lastCapturedThumbnail: UIImage?

    // Concurrency Synchronization
    private let stateLock = NSLock()
    private var _safePreset: LookPreset = .cleanPunch
    public nonisolated var currentSafePreset: LookPreset {
        stateLock.lock()
        defer { stateLock.unlock() }
        return _safePreset
    }

    // AVFoundation Session
    public let captureSession = AVCaptureSession()
    private let videoOutput = AVCaptureVideoDataOutput()
    private let photoOutput = AVCapturePhotoOutput()
    private let sessionQueue = DispatchQueue(label: "livegraded.camera.sessionQueue")
    private var isConfigured = false

    // Metal & Core Image Rendering
    public var metalDevice: MTLDevice?
    public var ciContext: CIContext?
    public var onFrameProcessed: ((CIImage) -> Void)?

    private override init() {
        super.init()
        setupMetal()
    }

    private func setupMetal() {
        if let device = MTLCreateSystemDefaultDevice() {
            self.metalDevice = device
            self.ciContext = CIContext(mtlDevice: device, options: [
                .workingColorSpace: CGColorSpace(name: CGColorSpace.extendedSRGB)!,
                .cacheIntermediates: false
            ])
        } else {
            self.ciContext = CIContext(options: nil)
        }
    }

    // MARK: - Session Configuration

    public func checkCameraPermissions() async -> Bool {
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        switch status {
        case .authorized:
            return true
        case .notDetermined:
            return await AVCaptureDevice.requestAccess(for: .video)
        default:
            return false
        }
    }

    public func configureSession() {
        sessionQueue.async { [weak self] in
            guard let self = self, !self.isConfigured else { return }
            self.isConfigured = true

            self.captureSession.beginConfiguration()
            self.captureSession.sessionPreset = .photo

            // Setup Camera Input
            guard let videoDevice = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
                  let videoInput = try? AVCaptureDeviceInput(device: videoDevice),
                  self.captureSession.canAddInput(videoInput) else {
                self.captureSession.commitConfiguration()
                return
            }
            self.captureSession.addInput(videoInput)

            // Setup 60fps Video Data Output for Live Graded Viewfinder
            if self.captureSession.canAddOutput(self.videoOutput) {
                self.videoOutput.alwaysDiscardsLateVideoFrames = true
                self.videoOutput.videoSettings = [
                    kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA)
                ]
                self.videoOutput.setSampleBufferDelegate(self, queue: DispatchQueue(label: "livegraded.camera.videoQueue", qos: .userInteractive))
                self.captureSession.addOutput(self.videoOutput)

                if let connection = self.videoOutput.connection(with: .video), connection.isVideoOrientationSupported {
                    connection.videoOrientation = .portrait
                }
            }

            // Setup Photo Capture Output
            if self.captureSession.canAddOutput(self.photoOutput) {
                self.photoOutput.maxPhotoQualityPrioritization = .balanced
                self.captureSession.addOutput(self.photoOutput)
            }

            self.captureSession.commitConfiguration()
            self.captureSession.startRunning()

            DispatchQueue.main.async {
                self.isSessionRunning = self.captureSession.isRunning
            }
        }
    }

    // MARK: - Shutter Capture

    public func capturePhoto() {
        guard !isCapturing else { return }
        isCapturing = true

        let settings = AVCapturePhotoSettings()
        settings.photoQualityPrioritization = .balanced

        photoOutput.capturePhoto(with: settings, delegate: self)
    }
}

// MARK: - AVCaptureVideoDataOutputSampleBufferDelegate

extension CameraSessionManager: AVCaptureVideoDataOutputSampleBufferDelegate {
    public nonisolated func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

        let inputImage = CIImage(cvPixelBuffer: pixelBuffer)

        // Thread-safe immutable 3D LUT grading (Zero shared mutable state)
        let preset = currentSafePreset
        let outputImage = LUTPresets.shared.applyGrade(to: inputImage, preset: preset)

        DispatchQueue.main.async { [weak self] in
            self?.onFrameProcessed?(outputImage)
        }
    }
}

// MARK: - AVCapturePhotoCaptureDelegate

extension CameraSessionManager: AVCapturePhotoCaptureDelegate {
    public nonisolated func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        defer {
            DispatchQueue.main.async {
                self.isCapturing = false
            }
        }

        if let error = error {
            print("Photo capture error: \(error.localizedDescription)")
            return
        }

        guard let photoData = photo.fileDataRepresentation(),
              let sourceImage = UIImage(data: photoData) else {
            return
        }

        let ciInput: CIImage
        if let cgImage = sourceImage.cgImage {
            ciInput = CIImage(cgImage: cgImage)
        } else if let ci = CIImage(data: photoData) {
            ciInput = ci
        } else {
            return
        }

        // Apply thread-safe immutable 3D LUT
        let preset = currentSafePreset
        let outputCI = LUTPresets.shared.applyGrade(to: ciInput, preset: preset)

        let context = ciContext ?? CIContext(options: nil)
        guard let gradedCGImage = context.createCGImage(outputCI, from: outputCI.extent) else { return }

        let gradedUIImage = UIImage(cgImage: gradedCGImage, scale: sourceImage.scale, orientation: sourceImage.imageOrientation)

        // Save to dedicated "LiveGraded Photos" album
        AlbumManager.shared.save(gradedImage: gradedUIImage, rawData: photoData) { [weak self] result in
            DispatchQueue.main.async {
                if case .success = result {
                    self?.lastCapturedThumbnail = gradedUIImage
                    UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
                }
            }
        }
    }
}
