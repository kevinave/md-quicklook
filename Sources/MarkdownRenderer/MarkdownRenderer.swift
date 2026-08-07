import Foundation
import Markdown

/// Options controlling how Markdown is converted to HTML.
public struct MarkdownRenderingOptions {
    /// When `true`, raw HTML embedded in the Markdown source is passed through
    /// verbatim. When `false` (default) it is escaped and shown as literal text.
    /// Keeping this `false` prevents `<script>` injection from untrusted files.
    public var allowsRawHTML: Bool

    /// When `true` (default) highlight.js and a GitHub theme are embedded so code
    /// blocks are syntax highlighted in a `WKWebView`.
    public var enableSyntaxHighlighting: Bool

    public init(allowsRawHTML: Bool = false, enableSyntaxHighlighting: Bool = true) {
        self.allowsRawHTML = allowsRawHTML
        self.enableSyntaxHighlighting = enableSyntaxHighlighting
    }

    public static let `default` = MarkdownRenderingOptions()
}

/// Converts Markdown text into styled, self-contained HTML.
///
/// The output of ``renderFullHTMLDocument(from:title:options:)`` inlines all CSS
/// and JavaScript so it can be handed straight to `WKWebView.loadHTMLString` from
/// inside a sandboxed Quick Look extension without needing any network or extra
/// file access.
public enum MarkdownRenderer {

    /// Renders just the HTML body fragment (no `<html>`, CSS, or JS).
    ///
    /// A leading YAML front matter block is removed before parsing. See
    /// ``splitFrontMatter(from:)`` for why.
    public static func renderHTMLFragment(
        from markdown: String,
        options: MarkdownRenderingOptions = .default
    ) -> String {
        let document = Document(
            parsing: splitFrontMatter(from: markdown).body,
            options: [.parseBlockDirectives]
        )
        var visitor = HTMLMarkupVisitor(allowsRawHTML: options.allowsRawHTML)
        return visitor.visit(document)
    }

    /// Splits a leading YAML front matter block off the Markdown body.
    ///
    /// Front matter is a Jekyll/Hugo convention, not CommonMark. Left in place,
    /// `---\ntitle: x\n---` parses as a thematic break followed by a *setext*
    /// heading — the trailing `---` underlines the preceding lines — so the
    /// metadata renders as an oversized `<h2>` above the document.
    ///
    /// The block is returned verbatim and deliberately **not** parsed as YAML.
    /// Rendering it as-is still shows what the reader wants from a preview (which
    /// post, what date) without this renderer taking on YAML's semantics —
    /// nesting, multi-line scalars, quoting, comments — which it would then own
    /// forever for the sake of a header block.
    ///
    /// Both `---` and `...` are accepted as terminators, per the YAML spec. An
    /// unterminated block is not front matter and is left alone.
    static func splitFrontMatter(from markdown: String) -> (frontMatter: String?, body: String) {
        func withoutCR(_ line: String) -> String {
            line.hasSuffix("\r") ? String(line.dropLast()) : line
        }

        let lines = markdown.components(separatedBy: "\n")
        guard let first = lines.first, withoutCR(first) == "---" else {
            return (nil, markdown)
        }

        for index in 1..<lines.count {
            let line = withoutCR(lines[index])
            guard line == "---" || line == "..." else { continue }
            let block = lines[1..<index].map(withoutCR).joined(separator: "\n")
            let body = lines[(index + 1)...].joined(separator: "\n")
            return (block.isEmpty ? nil : block, body)
        }

        return (nil, markdown)
    }

    /// Renders a complete, self-contained HTML document with inlined CSS/JS.
    public static func renderFullHTMLDocument(
        from markdown: String,
        title: String = "Markdown Preview",
        options: MarkdownRenderingOptions = .default
    ) -> String {
        let (frontMatter, markdownBody) = splitFrontMatter(from: markdown)
        let body = renderHTMLFragment(from: markdownBody, options: options)
        let escapedTitle = HTMLEscaping.escapeText(title)

        let header = frontMatter.map {
            "<div class=\"front-matter\"><pre>\(HTMLEscaping.escapeText($0))</pre></div>\n"
        } ?? ""

        var styles = ""
        styles += "<style>\n\(BundledAsset.githubMarkdownCSS)\n</style>\n"
        styles += "<style>\n\(layoutCSS)\n</style>\n"

        var scripts = ""
        if options.enableSyntaxHighlighting {
            styles += "<style>\n\(BundledAsset.highlightLightCSS)\n</style>\n"
            styles += "<style>\n@media (prefers-color-scheme: dark) {\n\(BundledAsset.highlightDarkCSS)\n}\n</style>\n"
            scripts += "<script>\n\(BundledAsset.highlightJS)\n</script>\n"
            scripts += "<script>\n\(highlightInvocationJS)\n</script>\n"
        }

        return """
        <!DOCTYPE html>
        <html lang="en">
        <head>
        <meta charset="utf-8" />
        <meta name="viewport" content="width=device-width, initial-scale=1" />
        <meta name="color-scheme" content="light dark" />
        <title>\(escapedTitle)</title>
        \(styles)</head>
        <body>
        <article class="markdown-body">
        \(header)\(body)
        </article>
        \(scripts)</body>
        </html>
        """
    }

    /// Extra layout CSS layered on top of github-markdown-css to center content
    /// and give the preview comfortable padding.
    private static let layoutCSS = """
    html, body { margin: 0; padding: 0; }
    /* Full-bleed background matching github-markdown-css's canvas color so the
       centered content's side margins blend in, in both light and dark mode. */
    body { background-color: #ffffff; }
    @media (prefers-color-scheme: dark) { body { background-color: #0d1117; } }
    .markdown-body {
        box-sizing: border-box;
        min-width: 200px;
        max-width: 980px;
        margin: 0 auto;
        padding: 28px 36px 48px;
        background-color: transparent;
    }
    .markdown-body .anchor { display: none; }
    /* Front matter: present but visibly secondary to the document itself. */
    .markdown-body .front-matter {
        margin: 0 0 22px;
        padding: 9px 13px;
        border-left: 3px solid #d0d7de;
        border-radius: 0 5px 5px 0;
        background-color: rgba(127, 127, 127, 0.07);
    }
    .markdown-body .front-matter pre {
        margin: 0;
        padding: 0;
        background: none;
        border: 0;
        font-size: 0.8em;
        line-height: 1.6;
        color: #57606a;
        white-space: pre-wrap;
        overflow-wrap: anywhere;
    }
    @media (prefers-color-scheme: dark) {
        .markdown-body .front-matter { border-left-color: #30363d; }
        .markdown-body .front-matter pre { color: #8b949e; }
    }
    @media (max-width: 767px) {
        .markdown-body { padding: 16px; }
    }
    """

    private static let highlightInvocationJS = """
    document.addEventListener('DOMContentLoaded', function () {
        if (!window.hljs) { return; }
        document.querySelectorAll('pre code').forEach(function (block) {
            try { window.hljs.highlightElement(block); } catch (e) {}
        });
    });
    """
}
