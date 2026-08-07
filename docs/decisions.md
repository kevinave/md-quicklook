# Design decisions

Why this project is shaped the way it is. Written down so the reasoning does not
have to be rediscovered — particularly the decisions that look like omissions.

## Rendering architecture

Quick Look Markdown extensions come in three shapes, and **the privilege each one
needs is decided by its architecture**, not by how careful its author was:

| Architecture | Entitlements it forces | Cost |
|---|---|---|
| **Data-based** — extension returns HTML, the system renders it | `app-sandbox` alone | local images in the document do not load |
| WebView inside the extension | whole-system read, or whole-home read-write | large surface |
| AppKit TextKit | `app-sandbox` + `user-selected.read-only` | poor fidelity, and the most code of the three |

Widely used extensions sit in the middle row: hosting a WebView means loading
`![](./image.png)` yourself, which means a file-read exception. That is the
architecture asking, not the author being careless.

**This project takes the first row.** The extension hands the system a
self-contained HTML document and never draws. Consequences:

- No file entitlement is needed beyond the previewed file Quick Look already
  grants, so there is none.
- WebKit helper processes are known to be fragile inside Quick Look extension
  sandboxes. Here the WebView is the system's, in the system's process, so that
  fragility is not this extension's to carry.
- CSS and highlight.js must be inlined into the document, since nothing else can
  be fetched. That is what makes the preview work offline and without file access.

## One Markdown implementation

Both the extension and the `mdql` CLI go through `MarkdownRenderer`, which walks
the swift-markdown AST. Nothing re-parses Markdown by hand.

This is worth stating because the alternative is easy to reach for and fails
quietly. Inline syntax re-implemented with string scanning gets nested emphasis,
`**` inside inline code, backslash escapes and bracketed link labels wrong — and
it does not crash, it renders something that is not what the file says.
`Examples/inline-torture.md` is the regression file.

## YAML front matter is shown, not parsed

Front matter is a Jekyll/Hugo convention, not CommonMark. Left in the source,
`---\ntitle: x\n---` parses as a thematic break followed by a *setext* heading —
the trailing `---` underlines the preceding lines — so a draft's metadata renders
as an oversized `<h2>` above its own title.

The block is split off before parsing and rendered verbatim in a subdued box.
**It is deliberately not parsed as YAML.** Showing it as written already answers
what a preview is asked — which document, from when — without this renderer
taking ownership of nesting, multi-line scalars, quoting and comments. That is a
large and permanent liability in exchange for a header block.

## There is no size limit

An input cap was tried and removed. It is worth recording why, because "large
files should be capped" is a reflex.

Two questions decide whether a guard belongs:

1. **If I don't add it, who catches this?** Quick Look extensions are separate
   XPC processes whose lifecycle the system manages; a slow one is terminated
   without harming Finder. That policy exists, and is maintained by the platform.
   A cap here would override it with a guessed threshold — and the guess could
   only ever be half informed, since HTML layout and highlight.js run on the far
   side of XPC where this process cannot measure them.
2. **Is the failure loud or quiet?** A big file is slow. Slow is loud, immediate,
   and matches what anyone expects from a big file. Guard the quiet failures —
   silently truncated, corrupted, miscomputed — not the loud ones.

Both answers said no. The cap also **manufactured a quieter failure than the one
it prevented**: a document that stops early with the explanation below the fold.
A guard that is more silent than the thing it guards against is a net loss.

For reference, measured on an M-series machine, this extension's half of the work:

| input | HTML out | parse + emit |
|---|---|---|
| 500 KB | 1.1 MB | 190 ms |
| 1 MB | 2.2 MB | 370 ms |
| 4 MB | 8.4 MB | 1,425 ms |
| 10 MB | 20.8 MB | 3,506 ms |

A 4 MB document previews completely. It just takes a moment.

## Dependencies

Two, both from the platform vendor: `swift-markdown` (which brings
`swift-cmark`). `Package.resolved` is tracked, against the upstream project's
`.gitignore`, so that rebuilding at any later date resolves the same parser this
was verified against. The manifest asks for `from: "0.4.0"`, which floats.

`highlight.js` is vendored rather than fetched. The copy in this repository is
byte-identical to the official v11.9.0 release:

```
sha256  837a6fa5b0c736b52bbde2b2b6190f305da3fc9ed41681db5321507057b5c846
```

## Known trade-offs

Stated plainly rather than discovered later:

- **Local images do not display.** `![](./a.png)` cannot be loaded without a file
  entitlement, and not having that entitlement is the point. Remote images and
  data URIs are unaffected.
- **Remote images are unverified.** Rendering happens in the system's process,
  which has network access. Whether the system's WebView loads remote `<img>`
  in a preview has not been tested; if it does, pressing space on a document
  with remote images would make a request. Assume it might until measured.
- **No Mermaid, no LaTeX.** Not implemented, and not planned.
- **`.md` and `.markdown` only.** `.mdx`, `.qmd`, `.mdc` and `.rmd` currently map
  to dynamic UTIs. Hard-coding `dyn.*` identifiers is the wrong fix — they are
  derived from the extension string and change the moment an app registers the
  type properly. The right fix is a `UTImportedTypeDeclarations` entry in the
  host app's `Info.plist` binding those extensions to
  `net.daringfireball.markdown`.
- **Raw HTML is escaped by default.** `MarkdownRenderingOptions.allowsRawHTML`
  turns it on; the preview leaves it off, so a Markdown file cannot inject markup
  into its own preview.

## Notes on the platform

- `qlmanage` crashes in its own process on macOS 27 betas (`key cannot be nil`,
  raised on `com.apple.quicklook.qlextension.request`). It is not a signal about
  the extension. Verify rendering with `mdql` and integration in Finder.
- An ad-hoc signed `.appex` does register with `pluginkit` and does load, on
  macOS 27 betas included.
- Launching the host app is what registers the extension; `qlmanage -r` only
  reloads the legacy `.qlgenerator` mechanism, which macOS removed for third
  parties in Sonoma. Stripping the quarantine attribute is likewise unrelated,
  and actively wrong for a notarized app, whose ticket is what that attribute
  lets Gatekeeper check.

## Roadmap

Written as triggers rather than a to-do list, so a future reader knows when each
becomes worth doing rather than whether it is still on someone's list.

- **Local image support** — only if previews of image-heavy documents start being
  something worth having. It costs a file-read entitlement, which is the one
  property this design is built around. Not a small trade.
- **Wider file extensions** — when a `.mdx`, `.qmd` or `.mdc` file actually needs
  previewing. Via `UTImportedTypeDeclarations`, not `dyn.*`.
- **CJK typography** — if the default line height and punctuation handling start
  to grate in long Chinese documents. Currently github-markdown-css defaults.
- **Remote image behaviour** — measure it, then decide whether to block it.
- **Trimming the host app** — the app is larger than the extension it exists to
  carry. Only worth it if the menu bar entry stops being wanted.
