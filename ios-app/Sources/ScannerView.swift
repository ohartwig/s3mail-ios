// SPDX-FileCopyrightText: 2026 Kai Ole Hartwig <mail@ole-hartwig.eu>
// SPDX-License-Identifier: Apache-2.0

import AudioToolbox
import AVFoundation
import SwiftUI

/// The camera, reading one QR code and stopping.
///
/// Deliberately narrow: it recognises QR codes and nothing else, it reports the
/// first one it sees, and it shuts the session down straight afterwards. A
/// scanner left running is a camera left running, and this one has exactly one
/// job.
struct ScannerView: UIViewControllerRepresentable {
    let found: (String) -> Void

    func makeUIViewController(context: Context) -> ScannerController {
        let c = ScannerController()
        c.found = found
        return c
    }

    func updateUIViewController(_: ScannerController, context: Context) {}
}

final class ScannerController: UIViewController, AVCaptureMetadataOutputObjectsDelegate {
    var found: ((String) -> Void)?
    private let session = AVCaptureSession()
    private var done = false

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        guard let device = AVCaptureDevice.default(for: .video),
              let input = try? AVCaptureDeviceInput(device: device),
              session.canAddInput(input) else {
            // No camera - the simulator, or permission refused. Not an error
            // worth a dialog: the setup screen offers pasting the code, and
            // that path works everywhere.
            return
        }
        session.addInput(input)

        let output = AVCaptureMetadataOutput()
        guard session.canAddOutput(output) else { return }
        session.addOutput(output)
        output.setMetadataObjectsDelegate(self, queue: .main)
        output.metadataObjectTypes = [.qr]

        let preview = AVCaptureVideoPreviewLayer(session: session)
        preview.frame = view.layer.bounds
        preview.videoGravity = .resizeAspectFill
        view.layer.addSublayer(preview)

        // Off the main thread: starting a capture session blocks for a moment,
        // and on the main thread that moment is a frozen screen.
        Task.detached { [session] in session.startRunning() }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        if session.isRunning {
            Task.detached { [session] in session.stopRunning() }
        }
    }

    func metadataOutput(_: AVCaptureMetadataOutput,
                        didOutput objects: [AVMetadataObject],
                        from _: AVCaptureConnection) {
        // One code, once. Without the guard a code in frame fires this several
        // times a second and the setup screen flickers through the same value.
        guard !done,
              let object = objects.first as? AVMetadataMachineReadableCodeObject,
              let value = object.stringValue else { return }
        done = true
        AudioServicesPlaySystemSound(kSystemSoundID_Vibrate)
        found?(value)
    }
}
