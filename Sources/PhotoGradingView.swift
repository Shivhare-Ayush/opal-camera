import SwiftUI
import PhotosUI
import Photos
import CoreImage
import ImageIO

struct PhotoGradingView: View {
    @ObservedObject var camera: CameraSessionManager
    @ObservedObject var albumManager: AlbumManager
    @Binding var showFlywheel: Bool

    @State private var selectedItem: PhotosPickerItem?
    @State private var previewImage: UIImage?
    @State private var originalFullData: Data?
    @State private var currentAsset: PHAsset?
    @State private var gradedPreviewImage: UIImage?
    @State private var isComparingOriginal: Bool = false
    @State private var isSaving: Bool = false
    @State private var showSaveSuccess: Bool = false
    @State private var saveSuccessMessage: String = ""
    @State private var gradingTask: Task<Void, Never>?

    init(camera: CameraSessionManager, albumManager: AlbumManager, showFlywheel: Binding<Bool>) {
        self.camera = camera
        self.albumManager = albumManager
        self._showFlywheel = showFlywheel
    }

    var body: some View {
        VStack(spacing: 0) {
            // Main Canvas Area (90% Screen)
            GeometryReader { geo in
                ZStack {
                    if let imageToDisplay = isComparingOriginal ? previewImage : (gradedPreviewImage ?? previewImage) {
                        Image(uiImage: imageToDisplay)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: geo.size.width, height: geo.size.height)
                            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 18, style: .continuous)
                                    .stroke(Color.white.opacity(0.15), lineWidth: 1)
                            )
                            // Hold to Compare Original gesture
                            .gesture(
                                DragGesture(minimumDistance: 0)
                                    .onChanged { _ in
                                        if !isComparingOriginal && previewImage != nil {
                                            isComparingOriginal = true
                                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                        }
                                    }
                                    .onEnded { _ in
                                        isComparingOriginal = false
                                    }
                            )

                        // Mode / Comparison Pill Indicator
                        VStack {
                            HStack {
                                Spacer()
                                if isComparingOriginal {
                                    Text("ORIGINAL")
                                        .font(.system(size: 11, weight: .bold))
                                        .tracking(1.5)
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 5)
                                        .background(.ultraThinMaterial)
                                        .foregroundColor(.white)
                                        .clipShape(Capsule())
                                        .padding(14)
                                } else {
                                    Text(camera.activePreset.displayName.uppercased())
                                        .font(.system(size: 11, weight: .bold))
                                        .tracking(1.5)
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 5)
                                        .background(camera.activePreset.accentColor.opacity(0.85))
                                        .foregroundColor(.white)
                                        .clipShape(Capsule())
                                        .padding(14)
                                }
                            }
                            Spacer()

                            // Hint: Press & Hold to peek original
                            if previewImage != nil && !isComparingOriginal {
                                Text("Hold photo to compare original")
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundColor(.white.opacity(0.6))
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 6)
                                    .background(.ultraThinMaterial)
                                    .clipShape(Capsule())
                                    .padding(.bottom, 12)
                            }
                        }
                        .allowsHitTesting(false)
                    } else {
                        // Empty State: Prompt to select a photo
                        VStack(spacing: 16) {
                            Image(systemName: "photo.on.rectangle.angled")
                                .font(.system(size: 48))
                                .foregroundColor(.white.opacity(0.4))

                            Text("No Photo Loaded")
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundColor(.white)

                            Text("Choose a photo from your library to apply real-time 3D film grades.")
                                .font(.system(size: 13))
                                .foregroundColor(.white.opacity(0.6))
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 32)

                            PhotosPicker(selection: $selectedItem, matching: .images) {
                                HStack(spacing: 8) {
                                    Image(systemName: "plus.circle.fill")
                                    Text("Choose from Library")
                                }
                                .font(.system(size: 14, weight: .bold))
                                .padding(.horizontal, 20)
                                .padding(.vertical, 12)
                                .background(Color.white)
                                .foregroundColor(.black)
                                .clipShape(Capsule())
                                .shadow(radius: 6)
                            }
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Color.white.opacity(0.04))
                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .stroke(Color.white.opacity(0.12), lineWidth: 1)
                        )
                    }

                    // Save Success Toast
                    if showSaveSuccess {
                        VStack {
                            Spacer()
                            HStack(spacing: 8) {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.green)
                                Text(saveSuccessMessage)
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundColor(.white)
                            }
                            .padding(.horizontal, 18)
                            .padding(.vertical, 10)
                            .background(.ultraThinMaterial)
                            .clipShape(Capsule())
                            .overlay(Capsule().stroke(Color.white.opacity(0.2), lineWidth: 1))
                            .shadow(color: .black.opacity(0.4), radius: 10, y: 5)
                            .padding(.bottom, 20)
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                        }
                        .allowsHitTesting(false)
                    }
                }
            }
            .padding(.horizontal, 10)

            // Bottom Control Deck (Picker + Flywheel Island + Save Button)
            ZStack {
                HStack {
                    // Photos Picker Trigger
                    PhotosPicker(selection: $selectedItem, matching: .images) {
                        ZStack {
                            Circle()
                                .fill(Color.white.opacity(0.15))
                                .frame(width: 48, height: 48)
                            Image(systemName: "photo.stack")
                                .font(.system(size: 20))
                                .foregroundColor(.white)
                        }
                        .frame(width: 48, height: 48)
                        .contentShape(Circle())
                    }
                    .buttonStyle(.plain)

                    Spacer()

                    // Save Graded Photo Button
                    Button(action: saveGradedPhoto) {
                        ZStack {
                            Circle()
                                .stroke(Color.white.opacity(0.4), lineWidth: 3)
                                .frame(width: 68, height: 68)

                            Circle()
                                .fill(camera.activePreset.accentColor)
                                .frame(width: 56, height: 56)

                            if isSaving {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            } else {
                                Image(systemName: "square.and.arrow.down.fill")
                                    .font(.system(size: 22, weight: .bold))
                                    .foregroundColor(.white)
                            }
                        }
                        .frame(width: 68, height: 68)
                        .contentShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .disabled(previewImage == nil || isSaving)
                    .opacity(previewImage == nil ? 0.3 : 1.0)

                    Spacer()

                    // Empty placeholder to balance layout
                    Color.clear.frame(width: 48, height: 48)
                }
                .padding(.horizontal, 28)
                .padding(.bottom, 24)
                .padding(.top, 14)

                // Floating Island (Flywheel Opener)
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
                        .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .offset(y: -54)
                }
                .allowsHitTesting(false) // Container does not block clicks underneath
                .overlay(
                    // Interactive trigger sits strictly within capsule bounds
                    Button(action: {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                            showFlywheel.toggle()
                        }
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    }) {
                        Capsule().fill(Color.clear)
                            .frame(width: 160, height: 36)
                    }
                    .buttonStyle(.plain)
                    .offset(y: -54)
                )
            }
        }
        .onAppear {
            loadLatestLibraryPhotoIfAvailable()
        }
        .onChange(of: selectedItem) { newItem in
            Task {
                guard let data = try? await newItem?.loadTransferable(type: Data.self) else { return }

                // Decode-time downsample to max 1920 to eliminate peak RAM spikes
                let downsampled = downsample(data: data, maxDimension: 1920)

                await MainActor.run {
                    self.currentAsset = nil
                    self.originalFullData = data
                    self.previewImage = downsampled
                    if let downsampled = downsampled {
                        self.applyGrade(to: downsampled, preset: camera.activePreset)
                    }
                }
            }
        }
        .onChange(of: camera.activePreset) { newPreset in
            if let image = previewImage {
                applyGrade(to: image, preset: newPreset)
            }
        }
    }

    // MARK: - Thread-Safe Asynchronous Grading with Task Cancellation

    private func applyGrade(to image: UIImage, preset: LookPreset) {
        gradingTask?.cancel()

        gradingTask = Task.detached(priority: .userInitiated) {
            guard !Task.isCancelled else { return }
            guard let ciInput = CIImage(image: image) else { return }

            let outputCI = LUTPresets.shared.applyGrade(to: ciInput, preset: preset)

            guard !Task.isCancelled else { return }

            let colorSpace = CGColorSpace(name: CGColorSpace.extendedSRGB) ?? CGColorSpaceCreateDeviceRGB()
            let context = CIContext(options: [
                .workingColorSpace: colorSpace,
                .cacheIntermediates: false
            ])

            guard let cgImage = context.createCGImage(outputCI, from: outputCI.extent) else { return }
            guard !Task.isCancelled else { return }

            let graded = UIImage(cgImage: cgImage, scale: image.scale, orientation: image.imageOrientation)

            await MainActor.run {
                guard !Task.isCancelled else { return }
                self.gradedPreviewImage = graded
            }
        }
    }

    // MARK: - Full Resolution Export

    private func saveGradedPhoto() {
        isSaving = true
        let preset = camera.activePreset

        Task.detached(priority: .userInitiated) {
            var fullData: Data? = await self.originalFullData

            // If photo was auto-loaded from latest library asset, fetch original full data
            if fullData == nil, let asset = await self.currentAsset {
                fullData = await self.fetchFullAssetData(for: asset)
            }

            guard let dataToProcess = fullData ?? (await self.previewImage?.jpegData(compressionQuality: 0.95)),
                  let fullImage = UIImage(data: dataToProcess),
                  let ciInput = CIImage(image: fullImage) else {
                await MainActor.run { self.isSaving = false }
                return
            }

            let outputCI = LUTPresets.shared.applyGrade(to: ciInput, preset: preset)
            let context = CIContext(options: nil)

            guard let cgImage = context.createCGImage(outputCI, from: outputCI.extent) else {
                await MainActor.run { self.isSaving = false }
                return
            }

            let fullGradedImage = UIImage(cgImage: cgImage, scale: fullImage.scale, orientation: fullImage.imageOrientation)

            await MainActor.run {
                self.albumManager.save(gradedImage: fullGradedImage, rawData: dataToProcess) { result in
                    DispatchQueue.main.async {
                        self.isSaving = false
                        switch result {
                        case .success:
                            UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
                            self.saveSuccessMessage = "Saved to 'LiveGraded Photos'"
                            withAnimation { self.showSaveSuccess = true }
                            DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                                withAnimation { self.showSaveSuccess = false }
                            }
                        case .failure(let error):
                            self.saveSuccessMessage = "Failed: \(error.localizedDescription)"
                            withAnimation { self.showSaveSuccess = true }
                        }
                    }
                }
            }
        }
    }

    // MARK: - Decode-Time Memory Downsampler (ImageIO)

    private func downsample(data: Data, maxDimension: CGFloat) -> UIImage? {
        let options: [CFString: Any] = [
            kCGImageSourceShouldCache: false
        ]
        guard let imageSource = CGImageSourceCreateWithData(data as CFData, options as CFDictionary) else {
            return UIImage(data: data)
        }

        let downsampleOptions: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxDimension
        ]
        guard let downsampledImage = CGImageSourceCreateThumbnailAtIndex(imageSource, 0, downsampleOptions as CFDictionary) else {
            return UIImage(data: data)
        }
        return UIImage(cgImage: downsampledImage)
    }

    // MARK: - Auto-load Latest Library Photo

    private func loadLatestLibraryPhotoIfAvailable() {
        guard previewImage == nil else { return }

        let fetchOptions = PHFetchOptions()
        fetchOptions.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        fetchOptions.fetchLimit = 1

        let fetchResult = PHAsset.fetchAssets(with: .image, options: fetchOptions)
        guard let latestAsset = fetchResult.firstObject else { return }

        self.currentAsset = latestAsset

        let manager = PHImageManager.default()
        let requestOptions = PHImageRequestOptions()
        requestOptions.isSynchronous = false
        requestOptions.deliveryMode = .highQualityFormat
        requestOptions.isNetworkAccessAllowed = true

        manager.requestImage(for: latestAsset, targetSize: CGSize(width: 1440, height: 1920), contentMode: .aspectFit, options: requestOptions) { image, _ in
            if let image = image {
                DispatchQueue.main.async {
                    self.previewImage = image
                    self.applyGrade(to: image, preset: self.camera.activePreset)
                }
            }
        }
    }

    private func fetchFullAssetData(for asset: PHAsset) async -> Data? {
        await withCheckedContinuation { continuation in
            let options = PHImageRequestOptions()
            options.isSynchronous = false
            options.deliveryMode = .highQualityFormat
            options.isNetworkAccessAllowed = true

            PHImageManager.default().requestImageDataAndOrientation(for: asset, options: options) { data, _, _, _ in
                continuation.resume(returning: data)
            }
        }
    }
}
