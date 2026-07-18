import SwiftUI
import VisionKit
import AVFoundation
import UIKit

private enum BarcodeScannerAvailability {
    case checking
    case ready
    case permissionDenied
    case restricted
    case unsupported
    case temporarilyUnavailable
}

struct BarcodeScannerView: View {
    @Environment(\.presentationMode) var presentationMode
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase
    var onBarcodeDetected: (String) -> Void
    var onBarcodesDetected: (([String]) -> Void)?

    @State private var isRapidMode = false
    @State private var scannedBarcodes: [String] = []
    @State private var lastScannedBarcode: String?
    @State private var flashSuccess = false
    @State private var availability: BarcodeScannerAvailability = .checking

    var body: some View {
        Group {
            switch availability {
            case .ready:
                scannerContent
            case .checking:
                scannerCheckingView
            case .permissionDenied:
                scannerUnavailableView(
                    icon: "camera.fill",
                    title: "Camera access is off",
                    message: "Allow camera access in Settings to scan a barcode. Your current logging context will still be here when you return.",
                    primaryTitle: "Open Settings",
                    primaryAction: openSettings
                )
            case .restricted:
                scannerUnavailableView(
                    icon: "lock.shield",
                    title: "Camera access is restricted",
                    message: "This device currently prevents camera access. You can return and use search, a label photo, or manual entry instead."
                )
            case .unsupported:
                scannerUnavailableView(
                    icon: "barcode.viewfinder",
                    title: "Barcode scanning is not available",
                    message: "This device does not support live barcode recognition. Your food log has not changed."
                )
            case .temporarilyUnavailable:
                scannerUnavailableView(
                    icon: "camera.badge.ellipsis",
                    title: "Camera is temporarily unavailable",
                    message: "Another camera session or a system restriction may be active. Close it and try again.",
                    primaryTitle: "Try Again",
                    primaryAction: resolveCameraAvailability
                )
            }
        }
        .background(Color.black.ignoresSafeArea())
        .onAppear(perform: resolveCameraAvailability)
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                resolveCameraAvailability()
            }
        }
    }

    private var scannerContent: some View {
        ZStack {
            VisionKitScannerView(
                isRapidMode: isRapidMode,
                onBarcodeDetected: { barcode in
                    if isRapidMode {
                        handleRapidScan(barcode)
                    } else {
                        onBarcodeDetected(barcode)
                    }
                },
                onUnavailable: {
                    availability = .temporarilyUnavailable
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
    }

    private var scannerCheckingView: some View {
        VStack(spacing: AppSpacing.group) {
            ProgressView()
                .tint(.white)

            Text("Starting camera")
                .appTextRole(.control)
                .foregroundStyle(.white)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
    }

    private func scannerUnavailableView(
        icon: String,
        title: String,
        message: String,
        primaryTitle: String? = nil,
        primaryAction: (() -> Void)? = nil
    ) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.section) {
            Spacer()

            Image(systemName: icon)
                .appTextRole(.display)
                .foregroundStyle(.white)
                .frame(width: 72, height: 72)
                .background(Color.white.opacity(0.1), in: RoundedRectangle(
                    cornerRadius: AppRadius.surface,
                    style: .continuous
                ))
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: AppSpacing.compact) {
                Text(title)
                    .appTextRole(.display)
                    .foregroundStyle(.white)

                Text(message)
                    .appTextRole(.secondary)
                    .foregroundStyle(.white.opacity(0.72))
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let primaryTitle, let primaryAction {
                Button(primaryTitle, action: primaryAction)
                    .buttonStyle(AppActionButtonStyle(.primary))
            }

            Button("Use another logging method") {
                presentationMode.wrappedValue.dismiss()
            }
            .buttonStyle(AppActionButtonStyle(.ghost))
            .tint(.white)

            Spacer()
        }
        .padding(AppSpacing.section)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    private func resolveCameraAvailability() {
        guard DataScannerViewController.isSupported else {
            availability = .unsupported
            return
        }

        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            availability = DataScannerViewController.isAvailable ? .ready : .temporarilyUnavailable
        case .denied:
            availability = .permissionDenied
        case .restricted:
            availability = .restricted
        case .notDetermined:
            availability = .checking
            AVCaptureDevice.requestAccess(for: .video) { granted in
                DispatchQueue.main.async {
                    availability = granted && DataScannerViewController.isAvailable
                        ? .ready
                        : (granted ? .temporarilyUnavailable : .permissionDenied)
                }
            }
        @unknown default:
            availability = .temporarilyUnavailable
        }
    }

    private func openSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        openURL(url)
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
                withAnimation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.7)) {
                    isRapidMode.toggle()
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: isRapidMode ? "bolt.badge.clock.fill" : "bolt.slash.fill")
                        .foregroundColor(isRapidMode ? AppPalette.onBrand : .white)
                    Text(isRapidMode ? "Rapid Scan ON" : "Rapid Scan OFF")
                        .font(.subheadline.bold())
                        .foregroundColor(isRapidMode ? AppPalette.onBrand : .white)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(isRapidMode ? Color.brandPrimary.opacity(0.9) : Color.black.opacity(0.6), in: Capsule())
                .overlay(
                    Capsule().stroke(isRapidMode ? AppPalette.achievement : Color.white.opacity(0.3), lineWidth: 1.5)
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
                .stroke(flashSuccess ? AppPalette.positive : Color.white.opacity(0.8), style: StrokeStyle(lineWidth: flashSuccess ? 5 : 3, dash: flashSuccess ? [] : [10, 5]))
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
                                .foregroundColor(AppPalette.positive)
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
                        .foregroundColor(.brandForeground)
                    Text("Staging Tray (\(scannedBarcodes.count) items)")
                        .font(.headline.bold())
                        .foregroundColor(.white)
                    Spacer()
                    if !scannedBarcodes.isEmpty {
                        Button("Clear") {
                            withAnimation { scannedBarcodes.removeAll() }
                        }
                        .font(.caption.bold())
                        .foregroundColor(AppPalette.critical)
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
                            ForEach(Array(scannedBarcodes.enumerated()), id: \.offset) { _, code in
                                HStack(spacing: 4) {
                                    Image(systemName: "barcode")
                                    Text(code)
                                        .font(.caption.bold())
                                }
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(Color.brandPrimary.opacity(0.8), in: Capsule())
                                .foregroundColor(AppPalette.onBrand)
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
                    .foregroundColor(scannedBarcodes.isEmpty ? .white : AppPalette.onBrand)
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
    var onUnavailable: () -> Void

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
        
        do {
            try viewController.startScanning()
        } catch {
            AppLog.app.error("Unable to start barcode scanner: \(error.localizedDescription, privacy: .public)")
            DispatchQueue.main.async {
                onUnavailable()
            }
        }
        
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
