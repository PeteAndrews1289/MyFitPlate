import SwiftUI
import FirebaseFirestore
import AVFoundation

struct BarcodeScannerView: UIViewControllerRepresentable {
    @Environment(\.presentationMode) var presentationMode
    var onBarcodeDetected: (String) -> Void

    func makeCoordinator() -> Coordinator {
        return Coordinator(parent: self)
    }

    func makeUIViewController(context: Context) -> ScannerViewController {
        let viewController = ScannerViewController()
        viewController.delegate = context.coordinator
        return viewController
    }

    func updateUIViewController(_ uiViewController: ScannerViewController, context: Context) {}

    class Coordinator: NSObject, AVCaptureMetadataOutputObjectsDelegate {
        var parent: BarcodeScannerView

        init(parent: BarcodeScannerView) {
            self.parent = parent
        }

        func metadataOutput(_ output: AVCaptureMetadataOutput, didOutput metadataObjects: [AVMetadataObject], from connection: AVCaptureConnection) {
            if let metadataObject = metadataObjects.first,
               let readableObject = metadataObject as? AVMetadataMachineReadableCodeObject,
               let barcodeString = readableObject.stringValue {

                AudioServicesPlaySystemSound(SystemSoundID(kSystemSoundID_Vibrate))
                

                let workItem = DispatchWorkItem { [weak self] in
                    guard let self = self else { return }
                    self.parent.presentationMode.wrappedValue.dismiss()
                    self.parent.onBarcodeDetected(barcodeString)
                }
                DispatchQueue.main.async(execute: workItem)
            }
        }
    }
}

class ScannerViewController: UIViewController {
    var captureSession: AVCaptureSession?
    var previewLayer: AVCaptureVideoPreviewLayer!
    var delegate: AVCaptureMetadataOutputObjectsDelegate?

    override func viewDidLoad() {
        super.viewDidLoad()
        setupCamera()
        setupOverlay()
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        if let session = captureSession, !session.isRunning {
             DispatchQueue.global(qos: .background).async {
                 session.startRunning()
             }
        }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        if let session = captureSession, session.isRunning {
            session.stopRunning()
        }
    }

    func setupCamera() {
        captureSession = AVCaptureSession()
        guard let videoCaptureDevice = AVCaptureDevice.default(for: .video) else { return }
        let videoInput: AVCaptureDeviceInput
        do { videoInput = try AVCaptureDeviceInput(device: videoCaptureDevice) } catch { return }
        if captureSession?.canAddInput(videoInput) == true { captureSession?.addInput(videoInput) } else { captureSession = nil; return }
        let metadataOutput = AVCaptureMetadataOutput()
        if captureSession?.canAddOutput(metadataOutput) == true {
            captureSession?.addOutput(metadataOutput)
            metadataOutput.setMetadataObjectsDelegate(delegate, queue: DispatchQueue.main)
            metadataOutput.metadataObjectTypes = [.ean8, .ean13, .upce, .code39, .code128, .qr]
        } else { captureSession = nil; return }
        previewLayer = AVCaptureVideoPreviewLayer(session: captureSession!)
        previewLayer.frame = view.layer.bounds
        previewLayer.videoGravity = .resizeAspectFill
        view.layer.addSublayer(previewLayer)
         DispatchQueue.global(qos: .background).async { [weak self] in self?.captureSession?.startRunning() }
    }

    func setupOverlay() {
        let overlayView = UIView()
        overlayView.layer.borderColor = UIColor.green.cgColor
        overlayView.layer.borderWidth = 3
        overlayView.backgroundColor = UIColor.clear
        overlayView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(overlayView)
        NSLayoutConstraint.activate([
            overlayView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            overlayView.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            overlayView.widthAnchor.constraint(equalTo: view.widthAnchor, multiplier: 0.7),
            overlayView.heightAnchor.constraint(equalTo: overlayView.widthAnchor, multiplier: 0.5)
        ])
    }
     override func viewDidLayoutSubviews() {
         super.viewDidLayoutSubviews()
         previewLayer?.frame = view.layer.bounds
     }
}
