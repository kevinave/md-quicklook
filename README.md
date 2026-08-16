# md-quicklook

Press the spacebar on a `.md` file in Finder and read it rendered, not as source.

[![macOS](https://img.shields.io/badge/macOS-13+-000000?logo=apple&logoColor=white)](https://www.apple.com/macos/)
[![Swift](https://img.shields.io/badge/Swift-5.9+-F05138?logo=swift&logoColor=white)](https://swift.org)
[![License](https://img.shields.io/badge/license-MIT-green)](LICENSE)

![Pressing space on Markdown files in Finder and seeing them rendered — headings, tables, syntax-highlighted code, inline formatting](assets/markdown-quicklook-demo.gif)

macOS has shipped the `net.daringfireball.markdown` type identifier for years but
has never shipped anything that renders it, so Quick Look falls back to plain
text. This is a Quick Look preview extension that fills that gap, built to hold
as little of its own machinery as possible.

## What it is

A single Quick Look extension, plus a small menu bar app that exists to host and
register it, plus `mdql` — a command line tool that runs the same renderer, which
is what makes the rendering testable without Finder in the loop.

- Rendered previews for `.md` and `.markdown`: headings, tables, task lists,
  nested blockquotes, footnotes, GitHub-flavoured everything
- Syntax highlighted code blocks, offline — highlight.js is inlined, not fetched
- YAML front matter shown as metadata instead of being mangled into a heading
- Light and dark, following the system
- Non-UTF-8 files decoded rather than turned into mojibake — including GB18030
- **One entitlement in the preview extension: `com.apple.security.app-sandbox`**

<details>
<summary><b>Install</b> — no signed release; build it yourself</summary>

<br/>


```bash
brew install xcodegen
git clone https://github.com/kevinave/md-quicklook.git
cd md-quicklook
xcodegen generate
xcodebuild -project MarkdownQuickLook.xcodeproj -scheme MarkdownQuickLook \
  -configuration Release -derivedDataPath .build-xcode \
  ARCHS=arm64 ONLY_ACTIVE_ARCH=YES \
  CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY="-" DEVELOPMENT_TEAM="" build
cp -R .build-xcode/Build/Products/Release/MarkdownQuickLook.app /Applications/
open /Applications/MarkdownQuickLook.app
```

Launching it once is what registers the extension. Confirm with:

```bash
pluginkit -mAvvv -i com.kevinave.mdquicklook.QuickLookExtension
```

A leading `+` means registered and enabled. Then select a `.md` file in Finder and
press space.

`CODE_SIGN_IDENTITY="-"` is ad-hoc signing, which is enough to run on the machine
that built it. Substitute a Developer ID if you want to hand the app to someone
else, or the recipient will meet Gatekeeper.

</details>

## How it works

```text
Finder spacebar
  -> the system matches net.daringfireball.markdown to this extension
  -> QuickLookExtension.appex, in its own XPC process, granted read access
     to that one file and nothing else
  -> PreviewProvider reads and decodes it
  -> MarkdownRenderer: swift-markdown AST -> HTMLMarkupVisitor -> HTML,
     with CSS and highlight.js inlined into that one document
  -> QLPreviewReply(dataOfContentType: .html)
  -> the system renders the HTML in its own process
```

The pivot is the last two steps. This is a **data-based** preview
(`QLIsDataBasedPreview`): the extension returns bytes and draws nothing, so the
WebView belongs to the system, in the system's process. Everything else follows
from that.

**Least privilege isn't earned here, it's structural.** Nothing is drawn locally
and no local resources are loaded, so there is nothing to ask for beyond the file
Quick Look already hands over. Extensions that host their own WebView need a read
exception over the home directory or the whole file system in order to load an
image; this one needs no file entitlement at all.

**One Markdown implementation.** The extension and the `mdql` CLI both go through
`MarkdownRenderer`. Nothing re-parses Markdown by hand, so nested emphasis, `**`
inside inline code, escapes and bracketed link labels behave per CommonMark.
`Examples/inline-torture.md` is the regression file for exactly those.

**No supervisor of its own.** There is no size cap and no timeout. Quick Look
extensions are separate processes whose lifecycle the system manages, and that
policy is better than one invented here.

The reasoning behind these and the known trade-offs are in
[`docs/decisions.md`](docs/decisions.md).

<details>
<summary><b>Development</b></summary>

<br/>

```bash
swift test                                   # renderer tests, no Finder needed
swift run mdql Examples/inline-torture.md out.html
```

`qlmanage` is unreliable on macOS 27 betas — it crashes in its own process while
servicing extension requests. Use `mdql` to check rendering and Finder to check
integration.

</details>

## Relationship to the upstream project

This started from [jzone3/markdown-quicklook](https://github.com/jzone3/markdown-quicklook)
(MIT). It is not a GitHub fork — the code was carried into a fresh repository — but the
upstream commits are preserved in this repository's history. Three things changed:

| | upstream | here |
|---|---|---|
| Preview | `NSViewController` rendering `NSAttributedString` | data-based `QLPreviewProvider` returning HTML |
| Inline parsing | hand-rolled with string indices | the swift-markdown AST the project already depended on |
| Extension entitlements | `app-sandbox` + `user-selected.read-only` | `app-sandbox` |

Front matter handling, the wider decoding fallbacks, dependency pinning and the
removal of the input size cap came with those.

## License

[MIT](LICENSE), continuing the upstream license. Bundled and vendored assets keep
their own terms — see [`THIRD_PARTY_LICENSES.md`](THIRD_PARTY_LICENSES.md).
