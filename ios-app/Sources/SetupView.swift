// SPDX-FileCopyrightText: 2026 Kai Ole Hartwig <mail@ole-hartwig.eu>
// SPDX-License-Identifier: Apache-2.0

import SwiftUI
import S3mailKit

/// Setting the device up: point it at the code the assistant shows on the
/// desktop.
///
/// The QR code carries bucket, prefix, region and sender - and no keys. That is
/// the whole point of `wizard.Device()`: a photograph of the screen, a
/// screenshot in a chat, a shoulder in a café, none of them hand anybody
/// access. The key is typed in once, here, and goes straight into the keychain.
struct SetupView: View {
    @Bindable var device: Device
    @State private var scanned: Setup?
    @State private var accessKey = ""
    @State private var secret = ""
    @State private var pin = ""
    @State private var busy = false
    @State private var scanning = false
    @State private var pasted = ""

    var body: some View {
        NavigationStack {
            Form {
                if let scanned {
                    Section {
                        LabeledContent(t("setup.bucket"), value: scanned.bucket)
                        if !scanned.prefix.isEmpty {
                            LabeledContent(t("setup.prefix"), value: scanned.prefix)
                        }
                        LabeledContent(t("setup.region"), value: scanned.region)
                        if !scanned.from.isEmpty {
                            LabeledContent(t("setup.from"), value: scanned.from)
                        }
                    } header: {
                        Text(t("setup.mailbox"))
                    }
                    if scanned.needsPIN {
                        Section {
                            TextField(t("setup.pin"), text: $pin)
                                .keyboardType(.numberPad)
                                .textContentType(.oneTimeCode)
                                .font(.system(.title2, design: .monospaced))
                        } header: {
                            Text(t("setup.pin"))
                        } footer: {
                            Text(t("setup.pinHint"))
                        }
                        Section {
                            Button(t("setup.finishPairing")) { finish() }
                                .disabled(pin.count != 6 || busy)
                        }
                    } else {
                        // A code from before pairing worked this way: it carries
                        // no key at all and somebody types one. Kept because
                        // such codes exist on real screens, and refusing them
                        // would be a worse answer than a longer form.
                        Section {
                            TextField(t("setup.accessKey"), text: $accessKey)
                            SecureField(t("setup.secret"), text: $secret)
                        } header: {
                            Text(t("setup.deviceAccess"))
                        } footer: {
                            Text(t("setup.keysNotInCode"))
                        }
                        Section {
                            Button(t("setup.finish")) { adopt() }
                                .disabled(accessKey.isEmpty || secret.isEmpty)
                        }
                    }
                } else {
                    Section {
                        Button(t("setup.scan"), systemImage: "qrcode.viewfinder") {
                            scanning = true
                        }
                    } footer: {
                        Text(t("setup.whereIsTheCode"))
                    }
                    Section {
                        TextField(t("setup.orPaste"), text: $pasted,
                                  axis: .vertical)
                            .lineLimit(3...8)
                            .font(.system(.footnote, design: .monospaced))
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                        Button(t("setup.next")) { read(pasted) }
                            .disabled(pasted.isEmpty)
                    }
                }
            }
            .navigationTitle("s3mail")
            .sheet(isPresented: $scanning) {
                ScannerView { code in
                    scanning = false
                    read(code)
                }
            }
            .alert(device.problem ?? "", isPresented: Binding(
                get: { device.problem != nil },
                set: { if !$0 { device.problem = nil } })) {
                Button("OK", role: .cancel) {}
            }
        }
    }

    private func read(_ code: String) {
        do {
            scanned = try Setup.fromCode(code)
        } catch {
            device.problem = error.localizedDescription
        }
    }

    /// Opens the sealed key with the PIN and takes the mailbox.
    ///
    /// Off the main thread: unsealing costs about a second by design, and that
    /// second is what stands between a photograph of the code and the key
    /// inside it. On the main thread it would be a second of frozen screen.
    private func finish() {
        guard let scanned else { return }
        let code = scanned, typed = pin
        busy = true
        Task.detached {
            do {
                let ready = try code.unlock(pin: typed)
                await MainActor.run { device.adopt(ready); busy = false }
            } catch {
                await MainActor.run {
                    device.problem = error.localizedDescription
                    pin = ""
                    busy = false
                }
            }
        }
    }

    private func adopt() {
        guard let scanned else { return }
        device.adopt(Setup(bucket: scanned.bucket, prefix: scanned.prefix,
                           region: scanned.region, from: scanned.from,
                           label: scanned.label,
                           accessKey: accessKey.trimmingCharacters(in: .whitespaces),
                           secret: secret.trimmingCharacters(in: .whitespaces)))
    }
}
