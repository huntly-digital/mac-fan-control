# Max Preset and About Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add an exact-maximum Max preset and complete the approved About tab with direct GitHub links.

**Architecture:** Reuse the existing percentage-based `setPreset` request and transactional daemon path. Treat `100%` as an exact maximum boundary in `PresetPolicy`, model Max as a fixed app preset, and keep About text/URLs in a testable presentation namespace consumed by the existing SwiftUI settings view.

**Tech Stack:** Swift 6.2, SwiftUI, Swift Testing/XCTest, SwiftPM, privileged NSXPC helper, macOS 15+.

## Global Constraints

- Max is always exactly `100%` of each fan's current SMC-reported RPM range.
- Max is not configurable, persisted, or restored after launch, reconnect, or wake.
- Keep `Auto`, `Quiet`, `Balanced`, `Cool`, and `Max` in one 336-point horizontal row.
- Max uses `fanblades.fill` and orange styling only while active.
- Preserve transactional Auto rollback and all thermal, heartbeat, disconnect, sleep, wake, shutdown, and readback safeguards.
- Add no IPC command, dependency, arbitrary SMC access, or official binary distribution.
- About copy and all labels remain English.
- About links point only to `huntly-digital/mac-fan-control`.

---

### Task 1: Exact maximum policy and daemon behavior

**Files:**
- Modify: `Tests/FanCoreTests/PresetPolicyTests.swift`
- Modify: `Sources/FanCore/PresetPolicy.swift`
- Modify: `Tests/FanDaemonCoreTests/RequestProcessorTests.swift`

**Interfaces:**
- Consumes: `PresetPolicy.target(minimum:maximum:percentage:) throws -> Int`
- Produces: exact `maximum` when `percentage == 100`; existing rounded behavior for `1...99`

- [ ] **Step 1: Write the failing policy test**

Add:

```swift
func testOneHundredPercentReturnsExactReportedMaximum() throws {
  XCTAssertEqual(
    try PresetPolicy.target(minimum: 1_350, maximum: 5_349, percentage: 100),
    5_349
  )
}
```

- [ ] **Step 2: Run the policy test and verify RED**

Run:

```sh
rtk make test
```

Expected: the new assertion fails because current rounding returns `5_300`.

- [ ] **Step 3: Implement the exact boundary**

After the existing guard in `PresetPolicy.target`, add:

```swift
if percentage == 100 {
  return maximum
}
```

Keep the existing rounding and clamping path unchanged for `1...99`.

- [ ] **Step 4: Add the failing daemon integration test**

Add:

```swift
func testMaxPresetAppliesEachFansExactMaximum() async {
  let controller = PresetFanController()
  let processor = RequestProcessor(controller: controller)

  let result = await processor.handle(
    FanRequest(id: "max", command: .setPreset, percentage: 100)
  )

  XCTAssertTrue(result.response.ok)
  let calls = await controller.calls
  XCTAssertEqual(calls, ["snapshot", "manual:0:5000", "manual:1:6000", "snapshot"])
}
```

- [ ] **Step 5: Run core and daemon tests and verify GREEN**

Run:

```sh
rtk make test
```

Expected: policy, daemon integration, rollback, and safety tests pass.

- [ ] **Step 6: Commit the core behavior**

```sh
rtk git add Sources/FanCore/PresetPolicy.swift Tests/FanCoreTests/PresetPolicyTests.swift Tests/FanDaemonCoreTests/RequestProcessorTests.swift
rtk git commit -m "feat: add exact maximum fan preset policy"
```

### Task 2: Max app model, settings, and menu UI

**Files:**
- Create: `Tests/MFanControlAppTests/FanPresetTests.swift`
- Modify: `Sources/MFanControlApp/Models/FanPreset.swift`
- Modify: `Sources/MFanControlApp/Stores/PresetStore.swift`
- Modify: `Sources/MFanControlApp/Views/FanMenuView.swift`
- Modify: `Sources/MFanControlApp/Views/SettingsView.swift`

**Interfaces:**
- Consumes: `FanStore.applyPreset(_:percentage:)`
- Produces: `FanPreset.maximum`, `PresetStore.percentage(for: .maximum) == 100`

- [ ] **Step 1: Write failing app-model tests**

Create:

```swift
import Foundation
import Testing

@testable import MFanControlApp

@MainActor
@Suite("Fan presets")
struct FanPresetTests {
  @Test("visible presets end with fixed Max")
  func visibleOrder() {
    #expect(
      FanPreset.visible
        == [.automatic, .quiet, .balanced, .cool, .maximum]
    )
    #expect(FanPreset.maximum.title == "Max")
    #expect(FanPreset.maximum.systemImage == "fanblades.fill")
  }

  @Test("Max always resolves to one hundred percent")
  func fixedMaximumPercentage() {
    let suite = "MFanControlAppTests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    let store = PresetStore(defaults: defaults)

    #expect(store.percentage(for: .maximum) == 100)
    store.setPercentage(50, for: .maximum)
    #expect(store.percentage(for: .maximum) == 100)
  }
}
```

- [ ] **Step 2: Run the app test and verify RED**

Run:

```sh
rtk /usr/bin/env DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer CLANG_MODULE_CACHE_PATH=/tmp/mfan-clang-cache SWIFTPM_MODULECACHE_OVERRIDE=/tmp/mfan-swiftpm-cache xcrun swift test --filter FanPresetTests --disable-sandbox
```

Expected: compilation fails because `FanPreset.maximum` does not exist.

- [ ] **Step 3: Add the fixed app preset**

In `FanPreset`:

```swift
case maximum
```

Set:

```swift
static let visible: [FanPreset] = [
  .automatic, .quiet, .balanced, .cool, .maximum,
]
```

Add switch branches:

```swift
case .maximum: "Max"
```

and:

```swift
case .maximum: "fanblades.fill"
```

In `PresetStore.percentage(for:)`, return `100` for `.maximum`. In
`setPercentage`, include `.maximum` with `.automatic` and `.manual` in the
no-op branch.

- [ ] **Step 4: Add the read-only Settings row**

After `presetRow(.cool)`, add:

```swift
HStack {
  Label(FanPreset.maximum.title, systemImage: FanPreset.maximum.systemImage)
    .frame(width: 92, alignment: .leading)
  Text("Uses each fan’s reported maximum")
    .foregroundStyle(.secondary)
  Spacer()
  Text("100%")
    .monospacedDigit()
    .frame(width: 38, alignment: .trailing)
}
```

- [ ] **Step 5: Add active Max styling without changing other presets**

In `FanMenuView`, derive:

```swift
private func activeColor(for preset: FanPreset) -> Color {
  preset == .maximum ? .orange : .accentColor
}
```

Use this color for the selected button foreground, background opacity, and
stroke. Keep inactive foreground `.primary`, equal widths, current spacing,
caption scaling, and the 336-point panel width.

- [ ] **Step 6: Run app tests and verify GREEN**

Run the filtered `FanPresetTests` command from Step 2.

Expected: both tests pass.

- [ ] **Step 7: Commit the app preset**

```sh
rtk git add Tests/MFanControlAppTests/FanPresetTests.swift Sources/MFanControlApp/Models/FanPreset.swift Sources/MFanControlApp/Stores/PresetStore.swift Sources/MFanControlApp/Views/FanMenuView.swift Sources/MFanControlApp/Views/SettingsView.swift
rtk git commit -m "feat: add Max preset to the macOS interface"
```

### Task 3: Approved About copy and GitHub links

**Files:**
- Create: `Sources/MFanControlApp/Support/AboutPresentation.swift`
- Create: `Tests/MFanControlAppTests/AboutPresentationTests.swift`
- Modify: `Sources/MFanControlApp/Views/SettingsView.swift`

**Interfaces:**
- Produces: `AboutPresentation.productDescription`, `statusNote`, and three non-optional GitHub `URL` values
- Consumes: native SwiftUI `Link`

- [ ] **Step 1: Write the failing presentation test**

Create:

```swift
import Testing

@testable import MFanControlApp

@Suite("About presentation")
struct AboutPresentationTests {
  @Test("uses approved product copy and GitHub destinations")
  func approvedContent() {
    #expect(
      AboutPresentation.productDescription
        == "A source-only, safety-first menu bar utility for fan telemetry and bounded fixed-RPM control on Apple Silicon Macs."
    )
    #expect(
      AboutPresentation.statusNote
        == "Experimental software — validate support on your exact Mac before enabling manual control."
    )
    #expect(
      AboutPresentation.repositoryURL.absoluteString
        == "https://github.com/huntly-digital/mac-fan-control"
    )
    #expect(
      AboutPresentation.issuesURL.absoluteString
        == "https://github.com/huntly-digital/mac-fan-control/issues"
    )
    #expect(
      AboutPresentation.licenseURL.absoluteString
        == "https://github.com/huntly-digital/mac-fan-control/blob/main/LICENSE"
    )
  }
}
```

- [ ] **Step 2: Run the About test and verify RED**

Run:

```sh
rtk /usr/bin/env DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer CLANG_MODULE_CACHE_PATH=/tmp/mfan-clang-cache SWIFTPM_MODULECACHE_OVERRIDE=/tmp/mfan-swiftpm-cache xcrun swift test --filter AboutPresentationTests --disable-sandbox
```

Expected: compilation fails because `AboutPresentation` does not exist.

- [ ] **Step 3: Add the presentation constants**

Create `AboutPresentation.swift`:

```swift
import Foundation

enum AboutPresentation {
  static let productDescription =
    "A source-only, safety-first menu bar utility for fan telemetry "
    + "and bounded fixed-RPM control on Apple Silicon Macs."
  static let statusNote =
    "Experimental software — validate support on your exact Mac "
    + "before enabling manual control."
  static let repositoryURL = URL(
    string: "https://github.com/huntly-digital/mac-fan-control"
  )!
  static let issuesURL = URL(
    string: "https://github.com/huntly-digital/mac-fan-control/issues"
  )!
  static let licenseURL = URL(
    string: "https://github.com/huntly-digital/mac-fan-control/blob/main/LICENSE"
  )!
}
```

- [ ] **Step 4: Implement the About layout**

Replace the old description with separate `Text` views using the two approved
constants. Add a centered `HStack` with native `Link` controls:

```swift
HStack(spacing: 8) {
  Link("View on GitHub", destination: AboutPresentation.repositoryURL)
  Text("·").foregroundStyle(.tertiary)
  Link("Report an Issue", destination: AboutPresentation.issuesURL)
  Text("·").foregroundStyle(.tertiary)
  Link("MIT License", destination: AboutPresentation.licenseURL)
}
.font(.callout)
```

Keep the icon, app name, dynamic bundle version, semantic colors, and existing
Settings window dimensions.

- [ ] **Step 5: Run About and app tests and verify GREEN**

Run the filtered About test, then:

```sh
rtk make test
```

Expected: all tests pass.

- [ ] **Step 6: Commit the About update**

```sh
rtk git add Sources/MFanControlApp/Support/AboutPresentation.swift Tests/MFanControlAppTests/AboutPresentationTests.swift Sources/MFanControlApp/Views/SettingsView.swift
rtk git commit -m "feat: complete About project links"
```

### Task 4: Documentation, packaging, and live verification

**Files:**
- Modify: `README.md`
- Verify: `Products/MFanControl.app`

**Interfaces:**
- Consumes: `make test`, `script/build_and_run.sh --verify`, `script/verify_app.sh`
- Produces: a signed, running local app and user-facing documentation that includes Max

- [ ] **Step 1: Update README preset documentation**

Change the feature and usage lists so they name:

```text
Auto, Quiet, Balanced, Cool, and Max
```

Document that Max uses each fan's exact current SMC-reported maximum and is
not configurable.

- [ ] **Step 2: Run complete static and unit verification**

Run:

```sh
rtk git diff --check
rtk /bin/bash -n script/*.sh
rtk make test
```

Expected: all commands exit `0`.

- [ ] **Step 3: Build, sign, launch, and verify**

Run:

```sh
rtk ./script/build_and_run.sh --verify
rtk ./script/verify_app.sh Products/MFanControl.app
```

Expected: app launches; app and helper signatures are valid and share a
non-ad-hoc Team ID.

- [ ] **Step 4: Perform live UI verification**

Open the menu-bar panel and confirm:

- five preset buttons fit in one row without clipping;
- Max shows orange only while active;
- selecting Max reaches each displayed maximum RPM;
- Auto restores macOS control;
- About shows the approved copy and all three links;
- the panel and Settings window retain their current dimensions.

- [ ] **Step 5: Commit documentation**

```sh
rtk git add README.md docs/superpowers/plans/2026-07-28-max-preset-and-about.md
rtk git commit -m "docs: document Max preset workflow"
```

- [ ] **Step 6: Push current main**

```sh
rtk git push origin main
```

Expected: local `HEAD` and `origin/main` resolve to the same commit and the
working tree is clean.
