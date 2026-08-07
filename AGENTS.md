# Working in this repository

Read this before changing anything here. It records what the current design buys
and what changing it would cost, plus the platform traps that cost real time to
rediscover.

## What this is

A Quick Look preview extension for Markdown, a menu bar app that exists only to
host and register it, and `mdql`, a CLI running the same renderer.

Source of truth for *why* the design looks like this:
[`docs/decisions.md`](docs/decisions.md). Read it before proposing architecture
changes — several things that look like omissions are decisions.

## What the current shape costs, if you change it

Nothing here is a prohibition. These are the three places where a change that
looks local turns out to have a price attached, so that the price is known before
it is paid rather than after. `docs/decisions.md` has the longer reasoning.

**Putting a `WKWebView` in the extension costs a file entitlement.** The
extension is a data-based provider (`QLIsDataBasedPreview`): it returns HTML and
the system renders it, which is why it asks for nothing beyond the file Quick
Look already hands over. Draw locally and local resources have to be loaded
locally, which means a read exception over the home directory or the file system
— that is what comparable extensions carry. Worth it for local image support,
perhaps; worth knowing either way.

**Parsing Markdown by hand fails silently.** Everything goes through
`MarkdownRenderer` and the swift-markdown AST. The extension previously
re-implemented inline syntax with string indices, and the result was not a crash
but a preview that quietly disagreed with the file — wrong nested emphasis, `**`
eaten inside inline code, escapes rendered literally. If a second parsing path
appears, that is the failure to expect.

**The absence of a size cap is deliberate.** It reads like an oversight, so it
tends to get "fixed". Quick Look extensions are separate XPC processes the system
already terminates when they are slow, and a cap here overrides that with a
guessed threshold — one that could only ever be half informed, since HTML layout
and highlight.js run on the far side of XPC. A previous cap also traded a loud
failure (slow) for a quiet one (a document that stops early).

One genuine external obligation, from MIT rather than from anyone's preference:
**copyright lines and licence texts survive verbatim wherever they appear.**
Everything around them is expected to change — add a copyright line for a new
contributor, add a `THIRD_PARTY_LICENSES.md` entry when code is vendored, update
an entry's version, hash and provenance when the thing it describes is upgraded.
Stale provenance is its own defect. The obligation covers the notices, not the
files and not the metadata around them.

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
- **Registration follows the bundle identifier, and only one copy can hold it.**
  Two separate things put a copy in the running: building it anywhere on disk
  registers that build with LaunchServices, from which PlugInKit picks up the
  embedded appex; and launching an installed app asserts the registration for
  that copy. Either can take the identifier from the other, and the most recent
  one wins.

  The consequence is that **building to test is not a read-only act**: compiling
  this repository in a scratch directory silently repoints the registration at a
  temporary path, and previews fall back to plain text once that path is gone.
  So `pluginkit -mAvvv -i <id>` showing `+` is **not enough** on its own — `+`
  reports enablement, not location. Read the `Path` line and confirm it is the
  copy you meant.

  To recover: unregister the stray build, delete it, relaunch the installed app,
  then restart the services below.
- **Registration changes need Finder and Quick Look restarted to take effect.**
  They cache the previous resolution, so a corrected registration keeps producing
  the old (broken) preview until:
  ```bash
  killall -9 QuickLookUIService quicklookd 2>/dev/null
  killall Finder
  ```
  Skipping this makes a completed fix look like a failed one.

## Conventions

- Comments explain **why**, especially where the code is deliberately absent —
  a future reader should not "fix" the missing size cap.
- Do not leave tombstones. If something recorded here becomes untrue, correct it
  in place rather than appending a note that the old text was wrong.
- Changes to the render path come with tests. `Tests/MarkdownRendererTests` runs
  without Finder, Xcode, or a signing identity.
