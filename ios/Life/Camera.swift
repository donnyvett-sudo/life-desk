import SwiftUI
import UIKit

/// The system camera as a SwiftUI sheet. Returns one JPEG, already scaled down for upload.
struct CameraPicker: UIViewControllerRepresentable {
    var onImage: (Data) -> Void
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let p = UIImagePickerController()
        p.sourceType = UIImagePickerController.isSourceTypeAvailable(.camera) ? .camera : .photoLibrary
        p.delegate = context.coordinator
        return p
    }
    func updateUIViewController(_ vc: UIImagePickerController, context: Context) {}
    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: CameraPicker
        init(_ p: CameraPicker) { parent = p }
        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let img = info[.originalImage] as? UIImage, let data = Self.jpeg(img) { parent.onImage(data) }
            parent.dismiss()
        }
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) { parent.dismiss() }

        /// Longest side 1280 px, quality 0.7: enough for the model, small enough for a mobile connection.
        static func jpeg(_ img: UIImage, maxSide: CGFloat = 1280) -> Data? {
            let s = max(img.size.width, img.size.height)
            let scale = s > maxSide ? maxSide / s : 1
            let size = CGSize(width: img.size.width * scale, height: img.size.height * scale)
            let r = UIGraphicsImageRenderer(size: size)
            return r.jpegData(withCompressionQuality: 0.7) { _ in img.draw(in: CGRect(origin: .zero, size: size)) }
        }
    }
}
