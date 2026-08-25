// SPDX-FileCopyrightText: 2026 Kai Ole Hartwig <mail@ole-hartwig.eu>
// SPDX-License-Identifier: Apache-2.0

import SwiftUI
import S3mailKit

struct RootView: View {
    @Bindable var device: Device

    var body: some View {
        if let mailbox = device.mailbox {
            MailboxView(mailbox: mailbox)
        } else {
            SetupView(device: device)
        }
    }
}
