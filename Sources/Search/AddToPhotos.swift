import AppKit
import Photos

// "Add Image to Photos", in a picture's right-click menu, as Safari has it.
//
// Without it a picture goes to Photos by way of Downloads: saved, found in
// the Finder, dragged over. Here the bytes the page showed are fetched as
// Copy Image fetches them (ImageMenu.swift), a blob: picture included, and
// handed to Photos as they arrived: the JPEG the site served, a GIF with
// all its frames, nothing encoded again.
//
// Lun asks to add, and for nothing more: macOS puts the question the first
// time the item is chosen, and what it grants lets a picture be put in the
// library without anything in the library being seen. There is no sentence
// in the Info.plist for reading it (build.sh), so a request to read could
// not even be put. Nothing happens until the item is chosen, and nothing
// new goes over the network.

/// What a picture's menu can do with it, done this app's way rather than
/// WebKit's (see ImageMenu.swift).
enum ImageAction {
    case copy, download, photos
}

/// The Photos library, as far as adding one picture needs it. The Mac's own
/// in the app; a test's stands in, since the real one asks on screen.
struct PhotosDoor: Sendable {
    /// Whether this build can ask at all. macOS ends an app that touches
    /// the library with no sentence to put in the question: a run straight
    /// from `swift build`, with no Info.plist, has none.
    var canAsk: @Sendable () -> Bool
    /// Leave to add, asked for the first time and remembered by macOS.
    var access: @Sendable () async -> PHAuthorizationStatus
    /// The picture, added as the bytes it came in.
    var add: @Sendable (Data) async throws -> Void

    static let system = PhotosDoor(
        canAsk: { Bundle.main.object(forInfoDictionaryKey: "NSPhotoLibraryAddUsageDescription") != nil },
        access: { await PHPhotoLibrary.requestAuthorization(for: .addOnly) },
        add: { data in
            try await PHPhotoLibrary.shared().performChanges {
                PHAssetCreationRequest.forAsset().addResource(with: .photo, data: data, options: nil)
            }
        }
    )
}

extension Browser {
    nonisolated static let addToPhotosTitle = "Add Image to Photos"
    nonisolated static let addedToPhotos = "Added to Photos"
    nonisolated static let notAddedToPhotos = "Couldn't add that image"
    /// Said no to before, or not this Mac's to allow: where to change it.
    nonisolated static let photosRefused = "Allow Lun to add to Photos in System Settings › Privacy & Security"

    /// The picture at `url`, put in Photos, and a line saying how it went.
    func addImageToPhotos(at url: URL, in tab: Tab, through door: PhotosDoor = .system) {
        Task {
            let data = await imageData(at: url, in: tab)
            announce(await Browser.addToPhotos(data, through: door))
        }
    }

    /// What is said once `data` has been offered to Photos. The picture is
    /// looked at before anything is asked: one that never arrived, or isn't
    /// a picture this process would decode (`reasonable`), asks for nothing.
    nonisolated static func addToPhotos(_ data: Data?, through door: PhotosDoor) async -> String {
        guard let data, reasonable(data), door.canAsk() else { return notAddedToPhotos }
        switch await door.access() {
        case .authorized, .limited:
            do {
                try await door.add(data)
                return addedToPhotos
            } catch {
                return notAddedToPhotos
            }
        case .denied, .restricted:
            return photosRefused
        default:
            // The question was put away unanswered: asked again next time.
            return notAddedToPhotos
        }
    }
}
