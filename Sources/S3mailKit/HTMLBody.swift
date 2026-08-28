// SPDX-FileCopyrightText: 2026 Kai Ole Hartwig <mail@ole-hartwig.eu>
// SPDX-License-Identifier: Apache-2.0

import SwiftUI
import WebKit

/// Showing a stranger's HTML.
///
/// This is the one place in the app where content somebody else wrote gets to
/// be more than text, so it is the one place worth being pedantic about. The
/// desktop's arrangement is copied deliberately rather than reinvented - the
/// same four measures, with the switches a WKWebView has instead of an
/// iframe's:
///
///   1. **No scripts.** The desktop uses `sandbox=""`; here it is
///      `allowsContentJavaScript = false` on the page configuration.
///   2. **A CSP in the document**, `default-src 'none'`, so nothing loads that
///      the mail did not bring with it.
///   3. **External images off by default.** A mail client that fetches remote
///      images hands every sender a read receipt: the request itself confirms
///      the address is read, when, and roughly from where.
///   4. **No navigation inside the view.** A tap opens Safari instead. A page
///      that could navigate in place could show a login form that looks like
///      part of the mail app.
///
/// Half of this would be worse than none, which is why it waited until it could
/// be done whole.
struct HTMLBody: UIViewRepresentable {
    let html: String
    let showImages: Bool
    /// Reported back so the view can size itself: a web view in a scroll view
    /// has no intrinsic height, and a fixed one either clips the mail or leaves
    /// a lake of white under a two-line note.
    let onHeight: (CGFloat) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onHeight: onHeight) }

    func makeUIView(context: Context) -> WKWebView {
        let pages = WKWebpagePreferences()
        pages.allowsContentJavaScript = false

        let config = WKWebViewConfiguration()
        config.defaultWebpagePreferences = pages
        // Nothing this page does may end up in the app's own storage.
        config.websiteDataStore = .nonPersistent()

        let view = WKWebView(frame: .zero, configuration: config)
        view.navigationDelegate = context.coordinator
        context.coordinator.watch(view)
        view.isOpaque = false
        view.backgroundColor = .clear
        view.scrollView.isScrollEnabled = false // the SwiftUI scroll view scrolls
        return view
    }

    func updateUIView(_ view: WKWebView, context: Context) {
        let document = Self.document(html: html, showImages: showImages)
        // Only when it actually changed, and that guard is the whole reason
        // anything is visible. SwiftUI calls updateUIView on every update, and
        // reporting the measured height *is* an update - so each finished load
        // started the next one, and the document was forever a fraction of the
        // way in. Headers, a "load images" button, and nothing under it.
        guard context.coordinator.loaded != document else { return }
        context.coordinator.loaded = document
        // No base URL: with one, a relative path in the mail would resolve
        // against it and fetch. Without, it resolves against nothing.
        view.loadHTMLString(document, baseURL: nil)
    }

    /// Wraps the mail in the policy. Built here rather than in the Go core: it
    /// is presentation, and the core has no opinion about viewports.
    static func document(html: String, showImages: Bool) -> String {
        let img = showImages ? "* data:" : "data:"
        let csp = "default-src 'none'; style-src 'unsafe-inline'; font-src data:; img-src \(img)"
        return """
        <!doctype html><html><head>\
        <meta http-equiv="Content-Security-Policy" content="\(csp)">\
        <meta name="viewport" content="width=device-width, initial-scale=1">\
        <style>
          :root { color-scheme: light dark; }
          body { font: -apple-system-body; margin: 0; word-break: break-word; }
          /* A mail laid out for a desktop is wider than a phone. Scaling it
             down would make it unreadable, so it may scroll sideways - inside
             its own box, never taking the page with it. */
          img, table { max-width: 100%; }
          pre { white-space: pre-wrap; }
        </style></head><body>\(html)</body></html>
        """
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        private let onHeight: (CGFloat) -> Void
        private var watching: NSKeyValueObservation?
        /// The document currently in the view, so an update that changed
        /// nothing does not restart the load. See updateUIView.
        var loaded: String?
        init(onHeight: @escaping (CGFloat) -> Void) { self.onHeight = onHeight }

        /// Watches how tall the document turned out.
        ///
        /// Through the scroll view and not through JavaScript, and that is the
        /// whole point: this page runs with `allowsContentJavaScript = false`,
        /// so `evaluateJavaScript("document.documentElement.scrollHeight")`
        /// never runs and never answers. The height then stayed at its initial
        /// 1 point and the mail was invisible — headers, a "load images"
        /// button, and nothing under it.
        ///
        /// It cost an evening to find because everything else was right: the
        /// HTML arrived, the view existed, the policy was correct. Only the one
        /// number that decides whether any of it can be seen was never read.
        func watch(_ view: WKWebView) {
            watching = view.scrollView.observe(\.contentSize, options: [.new]) {
                [weak self] scroll, _ in
                let height = scroll.contentSize.height
                if height > 1 { self?.onHeight(height) }
            }
        }

        /// Only the document this view loaded itself may load. Everything else
        /// is a link, and a link belongs in the browser.
        func webView(_ view: WKWebView,
                     decidePolicyFor action: WKNavigationAction,
                     decisionHandler done: @escaping (WKNavigationActionPolicy) -> Void) {
            guard action.navigationType != .other || action.request.url != nil else {
                return done(.allow)
            }
            // The initial loadHTMLString has no URL scheme worth following.
            if action.request.url == nil || action.request.url?.scheme == "about" {
                return done(.allow)
            }
            if action.navigationType == .linkActivated,
               let url = action.request.url,
               ["http", "https", "mailto", "tel"].contains(url.scheme ?? "") {
                UIApplication.shared.open(url)
            }
            // Everything not opened above is simply refused - including a
            // javascript: or data: URL somebody put in an href.
            done(.cancel)
        }

        func webView(_ view: WKWebView, didFinish navigation: WKNavigation!) {
            // The observation usually has it by now; this catches a document
            // whose size was final before anybody was watching.
            let height = view.scrollView.contentSize.height
            if height > 1 { onHeight(height) }
        }
    }
}
