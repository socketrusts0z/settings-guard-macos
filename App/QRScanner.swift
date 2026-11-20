import AVFoundation
import AppKit
import SwiftUI
import Vision

/// Capture and Vision run on one serial queue. Published UI state stays on main.
final class QRScanner: NSObject, ObservableObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    let session = AVCaptureSession()
    @Published private(set) var message = "Starting camera…"
    @Published private(set) var failed = false
    var onCode: ((String) -> Void)?

    private let queue = DispatchQueue(label: "com.anantchowdhary.frictionblocker.qr-camera")
    private var wantsCamera = false
    private var configured = false
    private var delivered = false
    private var lastScan: CFAbsoluteTime = 0

    func start() {
        queue.async { [self] in
            wantsCamera = true
            delivered = false
            switch AVCaptureDevice.authorizationStatus(for: .video) {
            case .authorized:
                startCapture()
            case .notDetermined:
                AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                    guard let self else { return }
                    self.queue.async {
                        guard self.wantsCamera else { return }
                        if granted { self.startCapture() }
                        else { self.report("Camera access was denied. Allow FrictionBlocker in System Settings → Privacy & Security → Camera, then retry.", failed: true) }
                    }
                }
            default:
                report("Camera access is unavailable. Allow FrictionBlocker in System Settings → Privacy & Security → Camera, then retry. You can also cancel and use your password.", failed: true)
            }
        }
    }

    func stop() {
        queue.async { [self] in
            wantsCamera = false
            if session.isRunning { session.stopRunning() }
        }
    }

    private func report(_ text: String, failed: Bool = false) {
        DispatchQueue.main.async { [weak self] in
            self?.message = text
            self?.failed = failed
        }
    }

    private func startCapture() {
        guard wantsCamera else { return }
        do {
            if !configured {
                session.beginConfiguration()
                defer { session.commitConfiguration() }
                session.inputs.forEach { session.removeInput($0) }
                session.outputs.forEach { session.removeOutput($0) }
                guard let camera = AVCaptureDevice.default(for: .video) else {
                    report("No camera found. Connect a webcam, then retry.", failed: true)
                    return
                }
                let input = try AVCaptureDeviceInput(device: camera)
                guard session.canAddInput(input) else {
                    report("The camera is unavailable. Close other apps using it, then retry.", failed: true)
                    return
                }
                session.addInput(input)
                if session.canSetSessionPreset(.high) { session.sessionPreset = .high }
                let output = AVCaptureVideoDataOutput()
                output.alwaysDiscardsLateVideoFrames = true
                output.setSampleBufferDelegate(self, queue: queue)
                guard session.canAddOutput(output) else {
                    session.removeInput(input)
                    report("Cannot read camera frames. Try another webcam.", failed: true)
                    return
                }
                session.addOutput(output)
                configured = true
            }
            session.startRunning()
            report(session.isRunning ? "Hold your QR code or barcode in view. Move it back if it looks blurry." : "The camera could not start. Close other camera apps, then retry.", failed: !session.isRunning)
        } catch {
            report("Could not start the camera: \(error.localizedDescription)", failed: true)
        }
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {
        guard wantsCamera, !delivered, CFAbsoluteTimeGetCurrent() - lastScan > 0.3,
              let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        lastScan = CFAbsoluteTimeGetCurrent()
        let request = VNDetectBarcodesRequest()
        do {
            request.symbologies = try request.supportedSymbologies()
            try VNImageRequestHandler(cvPixelBuffer: pixelBuffer, options: [:]).perform([request])
            let values = Set((request.results ?? []).compactMap(\.payloadStringValue)
                .filter(BarcodeUnlockPayload.isValid))
            guard values.count == 1, let token = values.first else {
                if values.count > 1 { report("Several codes are visible. Show only the code you want to use.") }
                return
            }
            delivered = true
            wantsCamera = false
            // Finish this sample callback before stopping the capture pipeline.
            queue.async { [self] in
                if session.isRunning { session.stopRunning() }
                DispatchQueue.main.async { [weak self] in self?.onCode?(token) }
            }
        } catch {
            wantsCamera = false
            queue.async { [self] in
                if session.isRunning { session.stopRunning() }
            }
            report("Could not process camera frames. Retry the camera, or cancel and use your password.", failed: true)
        }
    }
}

private final class CameraPreviewView: NSView {
    let previewLayer = AVCaptureVideoPreviewLayer()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        previewLayer.videoGravity = .resizeAspect
        layer?.addSublayer(previewLayer)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layout() {
        super.layout()
        previewLayer.frame = bounds
    }
}

private struct CameraPreview: NSViewRepresentable {
    let session: AVCaptureSession
    func makeNSView(context: Context) -> CameraPreviewView {
        let view = CameraPreviewView(frame: .zero)
        view.previewLayer.session = session
        return view
    }
    func updateNSView(_ view: CameraPreviewView, context: Context) {}
}

struct QRScannerView: View {
    let onCode: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var scanner = QRScanner()

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Scan your unlock code").font(.title2.bold())
            CameraPreview(session: scanner.session)
                .frame(width: 520, height: 340)
                .background(.black)
                .clipShape(RoundedRectangle(cornerRadius: 12))
            Text(scanner.message).frame(maxWidth: 520, alignment: .leading)
            Text("Camera frames are processed on this Mac and are not saved or uploaded.")
                .font(.caption).foregroundStyle(.secondary)
            HStack {
                if scanner.failed { Button("Retry Camera") { scanner.start() } }
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
            }
        }
        .padding(24)
        .onAppear {
            scanner.onCode = { token in onCode(token); dismiss() }
            scanner.start()
        }
        .onDisappear { scanner.onCode = nil; scanner.stop() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { scanner.start() } else { scanner.stop() }
        }
    }
}
