import SwiftUI
import UIKit
import PhotosUI

enum ProfilePhoto {
    /// Center-crops to a square and shrinks to 600px so it stays small on disk.
    static func prepare(_ data: Data) -> Data? {
        guard let image = UIImage(data: data) else { return nil }
        let side = min(image.size.width, image.size.height)
        let target: CGFloat = 600
        let scale = target / side
        let drawSize = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let rendered = UIGraphicsImageRenderer(size: CGSize(width: target, height: target), format: format).image { _ in
            image.draw(in: CGRect(x: (target - drawSize.width) / 2, y: (target - drawSize.height) / 2,
                                  width: drawSize.width, height: drawSize.height))
        }
        return rendered.jpegData(compressionQuality: 0.82)
    }

    /// Decoded images, so avatars don't re-decode JPEG data on every redraw.
    private static let cache = NSCache<NSString, UIImage>()

    static func image(for person: Person) -> UIImage? {
        guard let data = person.photoData else { return nil }
        let key = "\(person.id)-\(data.count)" as NSString
        if let hit = cache.object(forKey: key) { return hit }
        guard let image = UIImage(data: data) else { return nil }
        cache.setObject(image, forKey: key)
        return image
    }
}

/// "Take photo / Choose from library / Remove photo" menu wrapped around any label.
struct ProfilePhotoMenu<Label: View>: View {
    let hasPhoto: Bool
    let onPick: (Data) -> Void
    let onRemove: () -> Void
    @ViewBuilder let label: () -> Label

    @State private var libraryItem: PhotosPickerItem?
    @State private var showLibrary = false
    @State private var showCamera = false

    var body: some View {
        Menu {
            if UIImagePickerController.isSourceTypeAvailable(.camera) {
                Button("Take photo", systemImage: "camera") { showCamera = true }
            }
            Button("Choose from library", systemImage: "photo.on.rectangle") { showLibrary = true }
            if hasPhoto {
                Button("Remove photo", systemImage: "trash", role: .destructive, action: onRemove)
            }
        } label: {
            label()
        }
        .photosPicker(isPresented: $showLibrary, selection: $libraryItem, matching: .images)
        .onChange(of: libraryItem) { _, item in
            guard let item else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self), let prepared = ProfilePhoto.prepare(data) {
                    onPick(prepared)
                }
                libraryItem = nil
            }
        }
        .fullScreenCover(isPresented: $showCamera) {
            FlyerCameraView { data in
                if let prepared = ProfilePhoto.prepare(data) { onPick(prepared) }
            }
            .ignoresSafeArea()
        }
    }
}
