import SwiftUI
import VisionKit
import AVFoundation

struct BarcodeScannerView: View {
    @Environment(\.presentationMode) var presentationMode
    var onBarcodeDetected: (String) -> Void

    var body: some View {
        if DataScannerViewController.isSupported && DataScannerViewController.isAvailable {
            ZStack {
                VisionKitScannerView(onBarcodeDetected: onBarcodeDetected)
                    .ignoresSafeArea()
                
                VStack {
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Color.white.opacity(0.8), style: StrokeStyle(lineWidth: 3, dash: [10, 5]))
                        .frame(width: 280, height: 160)
                        .overlay(
                            Text("Position barcode within the frame")
                                .font(.footnote)
                                .fontWeight(.semibold)
                                .foregroundColor(.white)
                                .padding(.bottom, -30),
                            alignment: .bottom
                        )
                }
            }
        } else {
            // Fallback for unsupported devices (like Simulators)
            VStack(spacing: 20) {
                Image(systemName: "camera.viewfinder")
                    .appFont(size: 60)
                    .foregroundColor(Color(UIColor.secondaryLabel))
                Text("Barcode scanning is not supported or camera access was denied on this device.")
                    .font(.headline)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
                Button("Close") {
                    presentationMode.wrappedValue.dismiss()
                }
                .buttonStyle(.borderedProminent)
            }
            .padding()
        }
    }
}

struct VisionKitScannerView: UIViewControllerRepresentable {
    @Environment(\.presentationMode) var presentationMode
    var onBarcodeDetected: (String) -> Void

    func makeCoordinator() -> Coordinator {
        return Coordinator(parent: self)
    }

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let viewController = DataScannerViewController(
            recognizedDataTypes: [.barcode()],
            qualityLevel: .fast,
            recognizesMultipleItems: false,
            isHighFrameRateTrackingEnabled: true,
            isPinchToZoomEnabled: true,
            isGuidanceEnabled: true,
            isHighlightingEnabled: true
        )
        viewController.delegate = context.coordinator
        
        // Start scanning immediately
        try? viewController.startScanning()
        
        return viewController
    }

    func updateUIViewController(_ uiViewController: DataScannerViewController, context: Context) {}
    
    static func dismantleUIViewController(_ uiViewController: DataScannerViewController, coordinator: Coordinator) {
        uiViewController.stopScanning()
    }

    class Coordinator: NSObject, DataScannerViewControllerDelegate {
        var parent: VisionKitScannerView
        private var hasDetected = false

        init(parent: VisionKitScannerView) {
            self.parent = parent
        }

        func dataScanner(_ dataScanner: DataScannerViewController, didTapOn item: RecognizedItem) {
            handleRecognizedItem(item)
        }

        func dataScanner(_ dataScanner: DataScannerViewController, didAdd addedItems: [RecognizedItem], allItems: [RecognizedItem]) {
            if let item = addedItems.first {
                handleRecognizedItem(item)
            }
        }
        
        private func handleRecognizedItem(_ item: RecognizedItem) {
            guard !hasDetected else { return }
            if case .barcode(let barcode) = item {
                if let payload = barcode.payloadStringValue {
                    hasDetected = true
                    // Vibrate to indicate success
                    AudioServicesPlaySystemSound(SystemSoundID(kSystemSoundID_Vibrate))
                    
                    DispatchQueue.main.async {
                        self.parent.presentationMode.wrappedValue.dismiss()
                        self.parent.onBarcodeDetected(payload)
                    }
                }
            }
        }
    }
}
