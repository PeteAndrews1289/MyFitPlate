import SwiftUI
import VisionKit
import AVFoundation

struct BarcodeScannerView: View {
    @Environment(\.presentationMode) var presentationMode
    var onBarcodeDetected: (String) -> Void
    var onBarcodesDetected: (([String]) -> Void)? = nil

    @State private var isRapidMode = false
    @State private var scannedBarcodes: [String] = []
    @State private var lastScannedBarcode: String?
    @State private var flashSuccess = false

    var body: some View {
        if DataScannerViewController.isSupported && DataScannerViewController.isAvailable {
            ZStack {
                VisionKitScannerView(
                    isRapidMode: isRapidMode,
                    onBarcodeDetected: { barcode in
                        if isRapidMode {
                            handleRapidScan(barcode)
                        } else {
                            onBarcodeDetected(barcode)
                        }
                    }
                )
                .ignoresSafeArea()

                VStack {
                    topControlBar
                    Spacer()
                    centerGuidanceFrame
                    Spacer()
                    bottomTraySection
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

    private var topControlBar: some View {
        HStack {
            Button {
                presentationMode.wrappedValue.dismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .appFont(size: 28)
                    .foregroundColor(.white.opacity(0.8))
            }
            .buttonStyle(.plain)

            Spacer()

            Button {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                    isRapidMode.toggle()
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: isRapidMode ? "bolt.badge.clock.fill" : "bolt.slash.fill")
                        .foregroundColor(isRapidMode ? .yellow : .white)
                    Text(isRapidMode ? "Rapid Scan ON" : "Rapid Scan OFF")
                        .font(.subheadline.bold())
                        .foregroundColor(.white)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(isRapidMode ? Color.brandPrimary.opacity(0.9) : Color.black.opacity(0.6), in: Capsule())
                .overlay(
                    Capsule().stroke(isRapidMode ? Color.yellow : Color.white.opacity(0.3), lineWidth: 1.5)
                )
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 20)
        .padding(.top, 16)
    }

    private var centerGuidanceFrame: some View {
        VStack {
            RoundedRectangle(cornerRadius: 16)
                .stroke(flashSuccess ? Color.green : Color.white.opacity(0.8), style: StrokeStyle(lineWidth: flashSuccess ? 5 : 3, dash: flashSuccess ? [] : [10, 5]))
                .frame(width: 280, height: 160)
                .overlay(
                    VStack(spacing: 4) {
                        Text(isRapidMode ? "Scan multiple barcodes seamlessly" : "Position barcode within the frame")
                            .font(.footnote)
                            .fontWeight(.semibold)
                            .foregroundColor(.white)
                        if let last = lastScannedBarcode, isRapidMode {
                            Text("Added: \(last)")
                                .font(.caption.bold())
                                .foregroundColor(.green)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 2)
                                .background(Color.black.opacity(0.7), in: Capsule())
                        }
                    }
                    .padding(.bottom, -36),
                    alignment: .bottom
                )
        }
    }

    @ViewBuilder
    private var bottomTraySection: some View {
        if isRapidMode {
            VStack(spacing: 12) {
                HStack {
                    Image(systemName: "tray.full.fill")
                        .foregroundColor(.brandPrimary)
                    Text("Staging Tray (\(scannedBarcodes.count) items)")
                        .font(.headline.bold())
                        .foregroundColor(.white)
                    Spacer()
                    if !scannedBarcodes.isEmpty {
                        Button("Clear") {
                            withAnimation { scannedBarcodes.removeAll() }
                        }
                        .font(.caption.bold())
                        .foregroundColor(.red)
                    }
                }

                if scannedBarcodes.isEmpty {
                    Text("Point camera at items to rapid-scan into tray...")
                        .font(.subheadline)
                        .foregroundColor(.white.opacity(0.6))
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, 8)
                } else {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(Array(scannedBarcodes.enumerated()), id: \.offset) { idx, code in
                                HStack(spacing: 4) {
                                    Image(systemName: "barcode")
                                    Text(code)
                                        .font(.caption.bold())
                                }
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(Color.brandPrimary.opacity(0.8), in: Capsule())
                                .foregroundColor(.white)
                            }
                        }
                    }
                    .frame(height: 36)
                }

                Button {
                    let list = scannedBarcodes
                    presentationMode.wrappedValue.dismiss()
                    if let onBarcodes = onBarcodesDetected {
                        onBarcodes(list)
                    } else if let first = list.first {
                        onBarcodeDetected(first)
                    }
                } label: {
                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                        Text("Lookup & Log All (\(scannedBarcodes.count))")
                    }
                    .font(.headline.bold())
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(scannedBarcodes.isEmpty ? Color.gray.opacity(0.6) : Color.brandPrimary)
                    .foregroundColor(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .disabled(scannedBarcodes.isEmpty)
                .buttonStyle(.plain)
            }
            .padding(16)
            .background(Color.black.opacity(0.85), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
            .transition(.move(edge: .bottom).combined(with: .opacity))
        } else {
            Spacer().frame(height: 40)
        }
    }

    private func handleRapidScan(_ barcode: String) {
        // Prevent rapid duplicate scanning within a short window
        guard lastScannedBarcode != barcode else { return }
        lastScannedBarcode = barcode
        scannedBarcodes.append(barcode)

        // Flash visual feedback & vibrate
        AudioServicesPlaySystemSound(SystemSoundID(kSystemSoundID_Vibrate))
        withAnimation(.easeInOut(duration: 0.15)) { flashSuccess = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            withAnimation(.easeInOut(duration: 0.15)) { flashSuccess = false }
        }

        // Allow same barcode to be scanned again after 2.5 seconds
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
            if lastScannedBarcode == barcode {
                lastScannedBarcode = nil
            }
        }
    }
}

struct VisionKitScannerView: UIViewControllerRepresentable {
    @Environment(\.presentationMode) var presentationMode
    var isRapidMode: Bool
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

    func updateUIViewController(_ uiViewController: DataScannerViewController, context: Context) {
        context.coordinator.parent = self
    }
    
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
            if case .barcode(let barcode) = item {
                if let payload = barcode.payloadStringValue {
                    if parent.isRapidMode {
                        DispatchQueue.main.async {
                            self.parent.onBarcodeDetected(payload)
                        }
                    } else {
                        guard !hasDetected else { return }
                        hasDetected = true
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
}
