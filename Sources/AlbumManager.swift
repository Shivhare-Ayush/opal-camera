import Photos
import UIKit

@MainActor
final class AlbumManager: ObservableObject {
    static let shared = AlbumManager()
    @Published var authorizationStatus: PHAuthorizationStatus = .notDetermined

    private init() {}

    // MARK: - Authorization

    func checkAuthorization() async {
        let status = PHPhotoLibrary.authorizationStatus(for: .addOnly)
        authorizationStatus = status
    }

    func requestAddOnlyPermission() async {
        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        authorizationStatus = status
    }

    private func ensureAuthorization() async throws {
        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        authorizationStatus = status
        guard status == .authorized || status == .limited else {
            throw NSError(domain: "AlbumManager", code: 1, userInfo: [NSLocalizedDescriptionKey: "Photo library access denied or limited"])
        }
    }

    // MARK: - Idempotent Collection

    private func fetchOrCreateLiveGradedCollection() async throws -> PHAssetCollection {
        let predicate = NSPredicate(format: "title = %@", "LiveGraded Photos")
        let fetchOptions = PHFetchOptions()
        fetchOptions.predicate = predicate

        let existing = PHAssetCollection.fetchAssetCollections(with: .album, subtype: .albumRegular, options: fetchOptions).firstObject

        if let collection = existing {
            return collection
        }

        return try await withCheckedThrowingContinuation { continuation in
            PHPhotoLibrary.performChanges({
                let _ = PHAssetCollectionChangeRequest.creationRequestForAssetCollection(withTitle: "LiveGraded Photos")
            }) { success, error in
                if let error = error {
                    continuation.resume(throwing: error)
                } else {
                    let refetched = PHAssetCollection.fetchAssetCollections(with: .album, subtype: .albumRegular, options: fetchOptions).firstObject
                    if let collection = refetched {
                        continuation.resume(returning: collection)
                    } else {
                        continuation.resume(throwing: NSError(domain: "AlbumManager", code: -3, userInfo: [NSLocalizedDescriptionKey: "Failed to persist created collection"]))
                    }
                }
            }
        }
    }

    // MARK: - Save

    func save(gradedImage: UIImage, rawData: Data? = nil, completion: @escaping (Result<Void, Error>) -> Void) {
        Task { @MainActor in
            do {
                try await ensureAuthorization()
                let collection = try await fetchOrCreateLiveGradedCollection()

                let gradedChangeRequest = PHAssetChangeRequest.creationRequestForAsset(from: gradedImage)
                guard let gradedPlaceholder = gradedChangeRequest.placeholderForCreatedAsset else {
                    completion(.failure(NSError(domain: "AlbumManager", code: -4, userInfo: [NSLocalizedDescriptionKey: "Failed to create graded asset"])))
                    return
                }

                PHPhotoLibrary.shared().performChanges({
                    let collectionChangeRequest = PHAssetCollectionChangeRequest(for: collection)
                    collectionChangeRequest?.addAssets([gradedPlaceholder])

                    if let rawData = rawData, let rawImage = UIImage(data: rawData) {
                        let rawChangeRequest = PHAssetChangeRequest.creationRequestForAsset(from: rawImage)
                        guard let rawPlaceholder = rawChangeRequest.placeholderForCreatedAsset else { return }
                        collectionChangeRequest?.addAssets([rawPlaceholder])
                    }
                }) { saved, error in
                    if let error = error {
                        completion(.failure(error))
                    } else {
                        completion(.success(()))
                    }
                }
            } catch {
                completion(.failure(error))
            }
        }
    }

    // MARK: - Cleanup

    func cleanupTestAlbum(completion: @escaping (Result<Int, Error>) -> Void) {
        Task { @MainActor in
            do {
                let collection = try await fetchOrCreateLiveGradedCollection()

                let fetchOptions = PHFetchOptions()
                let assets = PHAsset.fetchAssets(in: collection, options: fetchOptions)
                let count = assets.count

                guard count > 0 else {
                    completion(.success(0))
                    return
                }

                PHPhotoLibrary.shared().performChanges({
                    PHAssetChangeRequest.deleteAssets(assets)
                }) { success, error in
                    if let error = error {
                        completion(.failure(error))
                    } else {
                        completion(.success(count))
                    }
                }
            } catch {
                completion(.failure(error))
            }
        }
    }
}
