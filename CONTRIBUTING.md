# Contributing to G-Rump

Thanks for taking an interest. G-Rump is a native macOS AI coding agent
(Swift/SwiftUI) maintained by one person, so contributions that are small,
focused, and tested get merged fastest. This doc covers how to get building and
the handful of rules that CI enforces.

## Getting set up

You need a Mac running **macOS 14 (Sonoma) or later** and **Swift 5.9+**.

```bash
git clone https://github.com/Aphrodine-wq/G-Rump.git
cd G-Rump
make build      # Debug build (uses all CPU cores)
make run        # Build debug + launch the app
```

Dependencies resolve automatically through Swift Package Manager on the first
build. The build uses a local `.build` directory instead of `~/Library` to avoid
permission issues.

### Xcode vs. Command Line Tools

This matters more than it looks. `make build` and `make run` work with just the
Command Line Tools, but **`swift test` requires the full Xcode SDK** — the test
target links against frameworks the CLT-only toolchain doesn't ship. If tests
fail to build with missing-SDK errors, install Xcode and point at it:

```bash
sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
```

CI runs on `Xcode_16.2`, so that's a safe baseline.

### Running tests

```bash
swift test --parallel                                   # full suite (~1,449 checks)
swift test --filter GRumpTests.ModelsTests              # one test file
swift test --filter GRumpTests.ModelsTests/testFoo      # one test method
```

Use `--parallel` locally — it's what CI runs (`swift test --parallel -j $(sysctl -n hw.ncpu)`)
and a cold full build of ~54K LOC under `StrictConcurrency=complete` is slow
otherwise.

### XcodeGen (optional)

If you'd rather work in Xcode, `project.yml` defines the whole project (macOS
app, iOS app, server CLI, test bundle, Xcode extension). Generate it with:

```bash
brew install xcodegen
xcodegen generate
```

The `.xcodeproj` is generated, not committed — regenerate it when `project.yml`
changes.

## The SPM / SwiftData dual-path gotcha

Read this before you touch persistence. It trips up everyone once.

`SwiftDataModels.swift` has **two code paths behind a compile flag**:

- **Xcode builds** use real SwiftData `@Model` macros with CloudKit sync.
- **SPM builds** (`swift build` / `swift test`) set `GRUMP_SPM_BUILD` and fall
  back to plain `Codable` classes backed by a JSON file store
  (`GRumpPersistenceStore`).

The reason: **SwiftData `@Model` macros do not expand under `swift build`.** The
macro plugin only runs inside Xcode's build system. This isn't a bug to fix — it's
the reason the fallback exists.

Practical consequences:

- Any change to a persisted model (`SDConversation`, `SDMessage`, `SDChatThread`,
  `SDChatBranch`, `SDProject`, `SDMemoryEntry`) must be made in **both** paths, or
  the SPM build and the Xcode build drift apart.
- Don't assume `@Model` behavior (change tracking, relationships, CloudKit) exists
  in the SPM path. It doesn't — it's a Codable class writing JSON to
  `~/Library/Application Support/GRump/swiftdata_store.json`.
- If a test passes under `swift test` but the app misbehaves in Xcode (or vice
  versa), suspect the two paths have diverged.

## Hard rules

CI enforces these and will fail the build. Save yourself a round trip.

### No `print()`

`print()` anywhere in `Sources/GRump/` is a **hard CI failure**. Use
`GRumpLogger` with the right category:

`.general`, `.ai`, `.persistence`, `.skills`, `.memory`, `.proactive`,
`.migration`, `.spotlight`, `.notifications`, `.coreml`, `.capture`,
`.liveActivity`

```swift
GRumpLogger.ai.debug("streaming started for \(model)")
```

### SwiftLint strict

Lint runs in `--strict` mode over `Sources/GRump/`, so warnings fail the build.
Run it before you push:

```bash
brew install swiftlint
swiftlint lint --strict Sources/GRump/
```

Force unwraps are warned, not blocked — but don't add new ones without a reason.
CI also flags non-constant force unwraps (`)!`) for review.

### Prefer Swift Testing for new tests

New tests should use the **Swift Testing** framework (`@Test`, `#expect`,
`#require`) rather than XCTest. The existing suite is mixed; new coverage should
lean on the newer framework. Match the style of the file you're extending if
you're adding to an existing test.

## Making changes

- **Branch from `main`.** Keep the branch scoped to one thing.
- **Small, focused PRs.** A 40-line PR gets reviewed today; a 2,000-line one
  waits. Split unrelated changes.
- **Tests are required for behavior changes.** Fixing a bug or changing logic?
  Add or update a test that would have caught it. Pure refactors and docs don't
  need new tests, but say so in the PR.
- **Touch `CHANGELOG.md`** when behavior changes in a user-visible way.
- Make sure `swift test --parallel` and `swiftlint lint --strict Sources/GRump/`
  are both clean before you open the PR. The PR template lists the full
  checklist.

## Where things live

- **[ARCHITECTURE.md](./ARCHITECTURE.md)** — source layout, the onboarding gate,
  settings tabs, the frame loop, keyboard shortcuts.
- **[CLAUDE.md](./CLAUDE.md)** — the deepest map of the codebase: providers, the
  tool system, MCP layers, skills, soul, persistence, conventions. Start here
  when you're hunting for where a thing is implemented.

## AI-assisted contributions

Using an AI agent to help write your patch is fine and welcome — this is a coding
agent, after all. The bar is unchanged: **the human who submits the PR owns its
correctness.** You are responsible for understanding the diff, for the tests
passing, and for anything the model got subtly wrong. "The AI wrote it" is not a
review response. Read your own patch before you send it.
