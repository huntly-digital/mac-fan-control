# About Settings Design

## Goal

Make the About tab accurately describe MFanControl and provide direct links to
the project's GitHub repository, issue tracker, and MIT license.

## Scope

Only `AboutSettingsView` changes. The existing Settings window, tab structure,
icon, app name, and dynamic bundle version remain unchanged.

## Content

The product description is:

> A source-only, safety-first menu bar utility for fan telemetry and bounded
> fixed-RPM control on Apple Silicon Macs.

The status note is:

> Experimental software — validate support on your exact Mac before enabling
> manual control.

The wording matches the README without claiming verified support for every
Apple Silicon Mac.

## Links

Display these three links in one centered horizontal row below the description:

| Label | Destination |
| --- | --- |
| View on GitHub | `https://github.com/huntly-digital/mac-fan-control` |
| Report an Issue | `https://github.com/huntly-digital/mac-fan-control/issues` |
| MIT License | `https://github.com/huntly-digital/mac-fan-control/blob/main/LICENSE` |

Use native SwiftUI `Link` controls so macOS opens the URLs through the user's
default browser and provides standard link accessibility behavior. Separate
the links visually with centered dot separators.

## Layout

Keep the current centered, native macOS About composition:

1. fan icon;
2. `MFanControl`;
3. dynamic version;
4. two-line product description;
5. experimental-status note;
6. GitHub links.

Use semantic foreground styles and the existing maximum text width. The new
content must fit the current Settings window without scrolling or resizing it.

## Verification

- Build the Swift package successfully.
- Confirm all three URL constants exactly match the destinations above.
- Confirm the app version still comes from `CFBundleShortVersionString`.
- Confirm the About tab remains readable in both Light and Dark appearances.
- Confirm VoiceOver receives meaningful labels from the native `Link` controls.

## Non-goals

- No redesign of the other Settings tabs.
- No network requests or GitHub API integration.
- No additional documentation, donation, release, or update links.
- No change to the app icon, versioning, or distribution model.
