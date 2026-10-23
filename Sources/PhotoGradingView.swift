import SwiftUI
import PhotosUI
import Photos
import CoreImage

struct PhotoGradingView: View {
    @ObservedObject var camera: CameraSessionManager
    @ObservedObject var albumManager: AlbumManager
    @Binding var showFlywheel: Bool

    @State private var selectedItem: PhotosPickerItem?
    @State private var originalImage: UIImage?
    @State private var gradedImage: UIImage?
    @State private var isComparingOriginal: Bool = false
    @State private var isSaving: Bool = false
    @State private var showSaveSuccess: Bool = false
    @State private var saveSuccessMessage: String = ""

    init(camera: CameraSessionManager, albumManager: AlbumManager, showFlywheel: Binding<Bool>) {
        self.camera = camera
        self.albumManager = albumManager
        self._showFlywheel = showFlywheel
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Main Canvas Area (90% Screen)
            GeometryReader { geo in
                ZStack {
                    if let imageToDisplay = isComparingOriginal ? originalImage : (gradedImage ?? originalImage) {
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
                                        if !isComparingOriginal && originalImage != nil {
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
                            if originalImage != nil && !isComparingOriginal {
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
                                .fill(Color.white.opacity(0.12))
                                .frame(width: 48, height: 48)
                            Image(systemName: "photo.stack")
                                .font(.system(size: 20))
                                .foregroundColor(.white)
                        }
                    }

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
                    }
                    .disabled(originalImage == nil || isSaving)
                    .opacity(originalImage == nil ? 0.3 : 1.0)

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
                    }
                    .offset(y: -54)
                }
            }
        }
        .onAppear {
            loadLatestLibraryPhotoIfAvailable()
        }
        .onChange(of: selectedItem) { newItem in
            Task {
                if let data = try? await newItem?.loadTransferable(type: Data.self),
                   let image = UIImage(data: data) {
                    await MainActor.run {
                        self.originalImage = image
                        self.applyGrade(to: image, preset: camera.activePreset)
                    }
                }
            }
        }
        .onChange(of: camera.activePreset) { newPreset in
            if let image = originalImage {
                applyGrade(to: image, preset: newPreset)
            }
        }
    }

    // MARK: - Grading Logic

    private func applyGrade(to image: UIImage, preset: LookPreset) {
        guard let ciInput = CIImage(image: image) else { return }
        let filter = LUTPresets.shared.filter(for: preset)
        filter.setValue(ciInput, forKey: kCIInputImageKey)

        guard let outputCI = filter.outputImage else { return }
        let context = camera.ciContext ?? CIContext(options: nil)

        if let cgImage = context.createCGImage(outputCI, from: outputCI.extent) {
            self.gradedImage = UIImage(cgImage: cgImage, scale: image.scale, orientation: image.imageOrientation)
        }
    }

    private func saveGradedPhoto() {
        guard let graded = gradedImage, let original = originalImage else { return }
        isSaving = true

        let rawData = original.jpegData(compressionQuality: 0.95)

        albumManager.save(gradedImage: graded, rawData: rawData) { result in
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

    // MARK: - Auto-load Latest Library Photo

    private func loadLatestLibraryPhotoIfAvailable() {
        guard originalImage == nil else { return }

        // Fetch most recent photo
        let fetchOptions = PHFetchOptions()
        fetchOptions.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        fetchOptions.fetchLimit = 1

        let fetchResult = PHAsset.fetchAssets(with: .image, options: fetchOptions)
        guard let latestAsset = fetchResult.firstObject else { return }

        let manager = PHImageManager.default()
        let requestOptions = PHImageRequestOptions()
        requestOptions.isSynchronous = false
        requestOptions.deliveryMode = .highQualityFormat
        requestOptions.isNetworkAccessAllowed = true

        manager.requestImage(for: latestAsset, targetSize: CGSize(width: 1440, height: 1920), contentMode: .aspectFit, options: requestOptions) { image, _ in
            if let image = image {
                DispatchQueue.main.async {
                    self.originalImage = image
                    self.applyGrade(to: image, preset: self.camera.activePreset)
                }
            }
        }
    }
}
