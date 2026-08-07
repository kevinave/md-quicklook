import Foundation
import CoreGraphics
import UniformTypeIdentifiers
import QuickLook
import QuickLookUI   // macOS: QLPreviewReply / QLFilePreviewRequest live here
import MarkdownRenderer

/// The principal class of the Quick Look Preview Extension.
///
/// This is a *data-based* provider (`QLIsDataBasedPreview` in Info.plist): we hand
/// the system a self-contained HTML document and it renders that HTML in its own
/// process. Nothing is drawn inside this extension.
///
/// Two consequences follow, and both are the reason this design was chosen:
///
/// 1. **Correctness.** The HTML comes from `MarkdownRenderer`, which walks the
///    swift-markdown AST (`HTMLMarkupVisitor`). The previous view-controller based
///    implementation re-parsed inline syntax by hand with string indices, which
///    mis-rendered nested emphasis, `**` inside inline code, and escapes.
///
/// 2. **Least privilege.** Because no `WKWebView` lives in this extension, it needs
///    no file access beyond the previewed file itself. The entitlements are a
///    single `com.apple.security.app-sandbox`.
final class PreviewProvider: QLPreviewProvider, QLPreviewingController {

    // No size limit, on purpose. Quick Look extensions are separate XPC processes
    // whose lifecycle the system manages: a slow one is terminated without taking
    // Finder with it. Capping input here would override a maintained platform
    // policy with a guessed threshold — and the guess could only ever be half
    // informed, since HTML layout and highlight.js run on the far side of XPC
    // where this process cannot measure them. A preview that shows part of a
    // document is also a worse failure than one that is merely slow.

    func providePreview(for request: QLFilePreviewRequest) async throws -> QLPreviewReply {
        let fileURL = request.fileURL
        let title = fileURL.lastPathComponent
        let markdown = try Self.readMarkdown(at: fileURL)

        let html = MarkdownRenderer.renderFullHTMLDocument(
            from: markdown,
            title: title
        )

        let reply = QLPreviewReply(
            dataOfContentType: .html,
            contentSize: CGSize(width: 1000, height: 1200)
        ) { _ in
            Data(html.utf8)
        }
        reply.title = title
        reply.stringEncoding = .utf8
        return reply
    }

    // MARK: - Helpers

    /// Reads the file, preferring UTF-8 and falling back through the encodings
    /// that actually show up in the wild — including GB18030, so Markdown written
    /// on Simplified Chinese systems previews instead of turning into mojibake.
    /// A preview should never fail purely over text encoding.
    private static func readMarkdown(at url: URL) throws -> String {
        let data = try Data(contentsOf: url)

        if let utf8 = String(data: data, encoding: .utf8) {
            return utf8
        }

        // Honours a BOM and lets Foundation guess for the remaining cases.
        var detected = String.Encoding.utf8
        if let text = try? String(contentsOf: url, usedEncoding: &detected) {
            return text
        }

        let fallbacks: [String.Encoding] = [
            String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(
                CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue))),
            .utf16,
            .shiftJIS,
            .isoLatin1
        ]
        for encoding in fallbacks {
            if let text = String(data: data, encoding: encoding) {
                return text
            }
        }

        // Last resort: lossy decode. Never throws, so the preview still appears.
        return String(decoding: data, as: UTF8.self)
    }
}
