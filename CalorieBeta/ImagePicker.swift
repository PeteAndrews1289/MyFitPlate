import SwiftUI
import UIKit
import AVFoundation // Added for AVCaptureDevice to handle camera permissions.

// This struct integrates a UIKit UIImagePickerController into SwiftUI, allowing users to capture
// or select images (e.g., for food recognition in the "CalorieBeta" app).
struct ImagePicker: UIViewControllerRepresentable {
    // Environment variable to dismiss the picker (iOS 15+).
    @Environment(\.dismiss) var dismiss // Preferred dismissal method for iOS 15 and later.
    // Fallback environment variable for older iOS versions.
    @Environment(\.presentationMode) private var presentationMode // Used for iOS 14 dismissal.
    // Determines the source of the image (camera or photo library).
    var sourceType: UIImagePickerController.SourceType = .camera // Defaults to camera.
    // Closure to handle the selected image.
    var onImagePicked: (UIImage) -> Void // Callback to process the picked image.

    // Coordinator to manage the UIImagePickerController delegate methods.
    class Coordinator: NSObject, UINavigationControllerDelegate, UIImagePickerControllerDelegate {
        let parent: ImagePicker // Reference to the parent ImagePicker struct.

        init(parent: ImagePicker) {
            self.parent = parent // Stores the parent for accessing its properties.
        }

        // Called when the user finishes picking an image.
        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let image = info[.originalImage] as? UIImage { // Extracts the original image.
                parent.onImagePicked(image) // Passes the image to the callback.
            }
            // Dismisses the picker, using the appropriate method based on iOS version.
            if #available(iOS 15.0, *) {
                parent.dismiss() // Modern dismissal for iOS 15+.
            } else {
                parent.presentationMode.wrappedValue.dismiss() // Fallback for iOS 14.
            }
        }

        // Called when the user cancels the image picker.
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            // Dismisses the picker, using the appropriate method based on iOS version.
            if #available(iOS 15.0, *) {
                parent.dismiss() // Modern dismissal for iOS 15+.
            } else {
                parent.presentationMode.wrappedValue.dismiss() // Fallback for iOS 14.
            }
        }
    }

    // Creates a coordinator to handle delegate methods.
    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self) // Returns a new coordinator with a reference to self.
    }

    // Creates and configures the UIImagePickerController.
    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController() // Initializes the image picker.
        picker.delegate = context.coordinator // Sets the coordinator as the delegate.
        picker.sourceType = sourceType // Sets the source (camera or photo library).

        // Handles camera-specific setup if the source type is camera.
        if sourceType == .camera {
            let status = AVCaptureDevice.authorizationStatus(for: .video) // Checks camera permission status.
            switch status {
            case .denied, .restricted: // Handles denied or restricted access.
                print("❌ Camera access denied or restricted") // Logs the issue.
                // Optionally, show an alert or handle this in the parent view.
                return picker
            case .notDetermined: // Requests access if permission is not yet determined.
                AVCaptureDevice.requestAccess(for: .video) { granted in
                    if !granted {
                        print("❌ Camera access not granted") // Logs if access is denied.
                    }
                }
            case .authorized: // Proceeds if access is granted.
                break
            @unknown default: // Handles unexpected future cases.
                print("❌ Unknown camera authorization status") // Logs unknown status.
            }
            picker.cameraCaptureMode = .photo // Sets the camera to photo mode.
            picker.allowsEditing = false // Disables image editing (optional customization).
        }
        picker.modalPresentationStyle = .fullScreen // Presents the picker in full-screen mode.
        return picker
    }

    // Updates the UIImagePickerController (not needed in this case but required by protocol).
    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {
        // No updates needed for this implementation.
    }
}
