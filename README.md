# JSON Studio

A native macOS JSON editor. SwiftUI with AppKit interop, Swift 6 strict concurrency, fully
offline — no account, no upload, no telemetry.

**Status: early.** The domain layer is under construction; there is no usable application yet.
See [Status](#status) for what actually works.

---

## What it's for

Open or paste a JSON payload, find out immediately whether it's valid and **exactly where it
isn't**, inspect its structure, copy paths out of it, compare it against another payload, export it.

The one thing it aims to do better than the alternatives is **error location**. Every JSON tool
surveyed reports the position where its parser *noticed* a problem rather than where the problem
is — a missing comma gets flagged at the next property name, and the workaround developers actually
use is "check one line before the error." None reports more than one error at a time, and most
blank their tree the moment the document is mid-edit and invalid.

So the parser here is error-recovering and every error carries two positions: the **cause**, where
the fix goes, and the **detection point**, where the parser noticed. The copy names both.

That's the claim. Formatting and structural diff are table stakes — free tools do both well — and
this is not the right tool for a 500 MB payload.

---

## Architecture

The decisions that shape everything else:

- **The parser is hand-written and records source spans.** `JSONSerialization` cannot report
  positions, and positions are load-bearing: error location, editor↔tree bidirectional selection,
  path-from-cursor and bracket matching all read them. `JSONSerialization` is used in tests as a
  round-trip oracle and nowhere else.
- **Spans are UTF-16 code-unit offsets.** `NSTextView`, `NSRange` and `NSLayoutManager` are all
  UTF-16 based; storing UTF-8 byte offsets would mean converting on every selection change. Line
  and column are derived lazily, never stored.
- **The parser recovers rather than throwing.** It returns a partial tree *plus* an array of
  errors. A live editor spends most of its time on invalid input, and that's precisely when the
  tree needs to stay usable.
- **Numbers keep their source text.** `9007199254740993` does not survive a `Double`; the literal
  is preserved and numeric interpretation is a separate, caller-driven step.
- **Objects are an ordered array of members, not a dictionary.** Key order is preserved (formatting
  must not disturb it) and duplicate keys survive — legal JSON, almost always a bug, and worth
  warning about rather than silently discarding.
- **The domain is a separate package** (`Packages/JSONKit`) with zero UI imports, buildable for iOS
  and Linux, and exercised by a CLI so it's testable without any interface at all.
- **The editor is `NSTextView` + TextKit 2** behind `NSViewRepresentable`. No third-party editor
  package, no `WKWebView`. The line-number gutter is a custom `NSRulerView`.
- **No state is signalled by colour alone** — every state carries a colour, a glyph and a text
  label. The four diff states in particular cannot be distinguished by colour: measured worst-case
  contrast between them is 1.00–1.10 across normal, deuteranopic, protanopic *and* grayscale
  vision, which is a property of four colours sharing one background rather than a palette defect.

---

## Layout

```
Packages/JSONKit/        pure Swift domain — parser, formatter, diff, statistics. No UI.
  Sources/JSONKit/       Model · Lexer · Parser · Path · Format · Diff · Transform · Statistics
  Sources/jsonstudio-cli CLI, so the domain is exercisable with no interface
  Tests/JSONKitTests/
JSON Studio/             the app target (the folder name has a space; Xcode owns it)
  App · Document · Editor · Inspector · Compare · Palette · Settings · DesignSystem
Design/                  design tokens, the sample payload, screen artboards
  palette-measure.py     computes every contrast ratio; exits with a failure list
  sample-payload.json    the fixture every test and mockup uses
```

The app target uses file-system-synchronized groups, so any file added under `JSON Studio/` is
compiled in automatically — no `.pbxproj` editing to add sources.

---

## Build

```bash
# Domain package
swift build --package-path Packages/JSONKit
swift test  --package-path Packages/JSONKit
swift run   --package-path Packages/JSONKit jsonstudio-cli parse Design/sample-payload.json

# App (the scheme name has a space)
xcodebuild -scheme "JSON Studio" -destination 'platform=macOS' build

# Design system: verifies every contrast ratio, hue separation and colour-blind simulation
python3 Design/palette-measure.py
```

`palette-measure.py` is a check, not a document — it must pass before any palette change lands.

---

## Performance budgets

Enforced in CI. A regression is a build failure, not a note.

| Operation | Input | Budget |
|---|---|---|
| Tokenize + parse | 100 KB | < 10 ms |
| Tokenize + parse | 1 MB | < 100 ms |
| Tokenize + parse | 10 MB | < 1.5 s |
| Format (pretty) | 1 MB | < 80 ms |
| Structural diff | 1 MB × 1 MB | < 500 ms |
| Statistics walk | 1 MB | < 50 ms |
| Keystroke → visible highlight | any | < 16 ms |
| Main-thread block | any | **0 ms** |

---

## Status

| | |
|---|---|
| Design system | done — tokens, measured palette, error copy, screens |
| `JSONKit` model types | done — spans, line index, tree, errors. 34 tests |
| Tokenizer · parser | **not started** |
| Path resolver · formatter · statistics · diff · transforms | not started |
| Application | shell only — no working editor |

Requires macOS 15+. Planning documents, architecture decision records and the working log are kept
locally rather than committed.

---

## Licence

Not yet chosen.
