# Working in this repository

Read this before changing anything here. It records the invariants that make this
project what it is, and the platform traps that cost real time to rediscover.

## What this is

A Quick Look preview extension for Markdown, a menu bar app that exists only to
host and register it, and `mdql`, a CLI running the same renderer.

Source of truth for *why* the design looks like this:
[`docs/decisions.md`](docs/decisions.md). Read it before proposing architecture
changes — several things that look like omissions are decisions.

## Invariants — do not break these without saying so explicitly

1. **The extension draws nothing.** It is a data-based provider
   (`QLIsDataBasedPreview`) returning HTML; the system renders it. Introducing a
   `WKWebView` here would force a file-read entitlement and undo the project's
   main property.
2. **`QuickLookExtension.entitlements` stays at `app-sandbox` alone.** If a change
   seems to need another entitlement, the change is wrong, or it is a real
   trade-off that has to be raised rather than absorbed.
3. **One Markdown implementation.** Everything goes through `MarkdownRenderer`
   and the swift-markdown AST. Never hand-parse Markdown syntax — that is the
   specific defect this project was created to remove, and it fails silently.
4. **No size caps, no timeouts.** See `docs/decisions.md`. The platform manages
   extension lifecycle; do not re-implement that with a guessed threshold.
5. **`LICENSE` and `THIRD_PARTY_LICENSES.md` are not edited.** Vendored assets
   keep their notices. New vendored code means a new entry.
6. **Vendored assets are verified, not trusted.** `highlight.min.js` must stay
   byte-identical to an official release; the current hash is recorded in
   `docs/decisions.md`. If you update it, re-verify and update the hash.

## Build, test, verify

```bash
swift test                                        # renderer tests, no Finder
swift run mdql Examples/inline-torture.md out.html # inspect rendering directly
```

Full app build (Xcode's GUI is not required, only its command line tools):

```bash
xcodegen generate
xcodebuild -project MarkdownQuickLook.xcodeproj -scheme MarkdownQuickLook \
  -configuration Release -derivedDataPath .build-xcode \
  ARCHS=arm64 ONLY_ACTIVE_ARCH=YES \
  CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY="-" DEVELOPMENT_TEAM="" build
```

`ARCHS=arm64` matters: without it the x86_64 slice is built too and the wait
doubles for nothing.

Install over a previous build — unregister first, or two copies compete:

```bash
osascript -e 'quit app "MarkdownQuickLook"'
pluginkit -r /Applications/MarkdownQuickLook.app/Contents/PlugIns/QuickLookExtension.appex
trash /Applications/MarkdownQuickLook.app
cp -R .build-xcode/Build/Products/Release/MarkdownQuickLook.app /Applications/
open /Applications/MarkdownQuickLook.app        # launching is what registers it
pluginkit -mAvvv -i com.kevinave.mdquicklook.QuickLookExtension
```

A leading `+` on the last command means registered and enabled.

## Verification

`swift test` and `mdql` cover the renderer. They do not cover whether Quick Look
loads the extension — nothing automated does, for the reasons below. **Ask the
user to press space on a file and report, or send a screenshot.** Do not claim
the integration works on the strength of unit tests.

`Examples/inline-torture.md` is the regression file for inline parsing. Every
case in it has a stated expectation; check the rendered output against those
after touching anything in the render path.

## Platform traps

Each of these has produced a wrong conclusion before.

- **`qlmanage` is not a reliable oracle.** On macOS 27 betas it crashes in its
  own process (`key cannot be nil`, on `com.apple.quicklook.qlextension.request`)
  while servicing extension requests. That crash says nothing about the
  extension. `qlmanage -p -o` also cannot serialize view-controller previews, so
  "did not produce any preview" is not evidence of failure either.
- **`QLPreviewReply` and `QLFilePreviewRequest` are in `QuickLookUI`**, not
  `QuickLook`. Importing only the latter fails with "cannot find type".
- **Launching the host app is what registers the extension.** `qlmanage -r`
  reloads the legacy `.qlgenerator` mechanism, which macOS removed for third
  parties in Sonoma; it does nothing here.
- **Do not strip the quarantine attribute** to work around Gatekeeper. For a
  notarized app that attribute is what lets Gatekeeper check the ticket, so
  removing it discards the evidence of legitimacy rather than supplying it.
- **Ad-hoc signed extensions do work** locally, macOS 27 betas included. A
  Developer ID is only needed to hand the app to someone else.
- **Xcode's GUI may refuse to launch on a beta macOS** while `xcodebuild`,
  `swift` and `clang` from the same install work fine. A failure to open Xcode is
  not a reason to abandon a build.

## Conventions

- Comments explain **why**, especially where the code is deliberately absent —
  a future reader should not "fix" the missing size cap.
- Do not leave tombstones. If something recorded here becomes untrue, correct it
  in place rather than appending a note that the old text was wrong.
- Changes to the render path come with tests. `Tests/MarkdownRendererTests` runs
  without Finder, Xcode, or a signing identity.
