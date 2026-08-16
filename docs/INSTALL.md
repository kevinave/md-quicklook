# Install runbook

A mechanical checklist for building this from source and confirming Quick Look
actually picked it up. Written for an agent doing the install on the user's Mac,
but it reads fine by hand.

Conventions, and what the current design would cost to change, live in
[`AGENTS.md`](../AGENTS.md); read that first if you are also going to change code.

## 0. Prerequisites

```bash
xcode-select -p                 # any developer directory is fine
xcodebuild -version             # Xcode's GUI does not need to open
command -v xcodegen || brew install xcodegen
```

On a beta macOS the Xcode app may refuse to launch while its command line tools
work normally. That is not a blocker for this build.

## 1. Build

```bash
cd <repo>
xcodegen generate
xcodebuild -project MarkdownQuickLook.xcodeproj -scheme MarkdownQuickLook \
  -configuration Release -derivedDataPath .build-xcode \
  ARCHS=arm64 ONLY_ACTIVE_ARCH=YES \
  CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY="-" DEVELOPMENT_TEAM="" build
```

Expect `** BUILD SUCCEEDED **` and `Signing Identity: "Sign to Run Locally"`.

`CODE_SIGN_IDENTITY="-"` is ad-hoc signing. It is sufficient on the machine that
built the app. `security find-identity -v -p codesigning` reporting zero
identities is normal and not an error.

Omitting `ARCHS=arm64` builds an x86_64 slice nobody uses and doubles the wait.

## 2. Replace any previous install

Unregister before removing, or a stale registration lingers and can compete with
the new one.

```bash
osascript -e 'quit app "MarkdownQuickLook"' 2>/dev/null
pluginkit -r /Applications/MarkdownQuickLook.app/Contents/PlugIns/QuickLookExtension.appex 2>/dev/null
trash /Applications/MarkdownQuickLook.app 2>/dev/null
```

If the previous install used a different bundle identifier, unregister that one
by id as well:

```bash
pluginkit -m -p com.apple.quicklook.preview -vvv | grep -i quicklook
```

## 3. Install and register

```bash
cp -R .build-xcode/Build/Products/Release/MarkdownQuickLook.app /Applications/
open /Applications/MarkdownQuickLook.app
```

**Launching the app is what registers this copy of the extension**, and it is the
step people skip. `qlmanage -r` does not do it: that only reloads the legacy
`.qlgenerator` mechanism, which macOS removed for third parties in Sonoma.

Note that launching is not the *only* thing that can register an appex —
building a copy elsewhere registers that build too, and whichever happened last
holds the bundle identifier. That is why step 2 removes previous installs and
step 4 checks the `Path`, not just the `+`. See the registration entry in
[`AGENTS.md`](../AGENTS.md).

## 4. Confirm registration

```bash
pluginkit -mAvvv -i com.kevinave.mdquicklook.QuickLookExtension
```

Check two things in that output, not one.

**The leading marker.** `+` means registered and enabled. `-` means present but
disabled; enable it in System Settings → General → Login Items & Extensions →
Quick Look.

**The `Path` line.** It must be inside `/Applications/MarkdownQuickLook.app`. A
`+` on its own does not tell you which copy holds the identifier, so if some
other build claimed it — a build in a scratch directory is enough — this step
passes while the preview keeps using a copy that may not survive the day. When
the path is wrong, go back to step 2, unregister and delete that copy, then
repeat step 3.

```bash
pluginkit -mAvvv -i com.kevinave.mdquicklook.QuickLookExtension | grep Path
# expect: Path = /Applications/MarkdownQuickLook.app/Contents/PlugIns/QuickLookExtension.appex
```

Confirm no other extension claims the same type:

```bash
pluginkit -mAvvv -p com.apple.quicklook.preview | grep -v com.apple
```

## 5. Verify rendering

Check the renderer without involving Finder:

```bash
swift test
swift run mdql Examples/inline-torture.md /tmp/torture.html
```

`Examples/inline-torture.md` states an expectation for each case; compare.

## 6. Verify integration — ask the user

**Nothing automated covers whether Quick Look loads the extension.**

- `qlmanage -p -o` cannot serialize every preview kind, so an empty result proves
  nothing.
- On macOS 27 betas `qlmanage` crashes in its own process (`key cannot be nil`,
  on `com.apple.quicklook.qlextension.request`). That is the tool failing, not
  the extension.

So: ask the user to select a `.md` file in Finder, press space, and report what
they see — a screenshot is better. Do not report the install as working on the
strength of steps 1–5 alone.

Useful files to suggest: `Examples/inline-torture.md` for inline parsing, and any
document with YAML front matter for the metadata block.

## Troubleshooting

**Nothing happens on space.** Check step 4 first. If the extension is absent from
the list entirely, move the app to the Trash, put it back in `/Applications`, and
launch it again — that forces re-registration.

**The preview shows plain text.** Another extension may have claimed the type, or
none matched. Check what the file's type actually resolves to:

```bash
mdls -name kMDItemContentType <file>.md
```

This project handles `net.daringfireball.markdown`. Other extensions such as
`.mdx` or `.qmd` resolve to `dyn.*` identifiers and are not handled; see the
trade-offs section of [`docs/decisions.md`](decisions.md).

**Previews are stale after a rebuild.** Repeat step 2 in full. The unregister is
the part that gets skipped and is usually the cause.
