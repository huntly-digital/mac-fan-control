# Max Preset Design

## Goal

Add a one-click Max preset that drives every detected fan to its own current
SMC-reported maximum RPM while preserving the existing safety and recovery
contract.

## Preset behavior

- Add `Max` after `Cool` in the visible preset order:
  `Auto`, `Quiet`, `Balanced`, `Cool`, `Max`.
- Max always represents `100%`; it is not user-configurable or persisted.
- At `100%`, `PresetPolicy` returns the exact reported `maximumRPM`. It does
  not round the maximum down to the nearest hundred.
- The daemon continues to apply the preset transactionally. If any fan fails,
  every fan returns to Auto.
- Existing thermal-pressure, heartbeat, disconnect, sleep, wake, shutdown,
  and verification behavior remains unchanged.

## Menu-bar presentation

Keep all five presets in one horizontal row inside the existing 336-point
panel. Reuse the compact equal-width button treatment and existing label
scaling.

Max uses:

- title: `Max`;
- SF Symbol: `fanblades.fill`;
- orange active foreground, border, and background treatment;
- the standard inactive appearance when it is not selected.

The other presets retain the current accent-color active state.

## Settings presentation

The Presets tab keeps editable sliders for Quiet, Balanced, and Cool. Add a
read-only Max row showing `100%` so the fixed behavior is visible without
suggesting that it can be changed.

## Data flow

1. Selecting Max resolves its percentage to `100`.
2. `FanStore` sends the existing typed `setPreset` request.
3. `RequestProcessor` computes one target per fan through `PresetPolicy`.
4. `PresetPolicy` returns each fan's exact reported maximum at `100%`.
5. Successful readback marks Max as the active preset.
6. Any failure follows the existing transactional Auto rollback.

No new IPC command, arbitrary SMC access, or persisted active state is added.

## Verification

- A policy test proves that `100%` returns an irregular maximum exactly, such
  as `5_349`, rather than `5_300`.
- A daemon test proves that Max applies each fan's distinct maximum.
- App-model tests cover visible order, title, icon, and fixed percentage.
- Existing rollback, thermal, heartbeat, and Auto-recovery tests remain green.
- A live menu-bar check confirms that five buttons fit the current width
  without clipping or increasing the panel height.

## Coordinated About update

The same implementation cycle also applies the already approved
[`2026-07-28-about-settings-design.md`](2026-07-28-about-settings-design.md):

- accurate source-only and safety-first English product copy;
- `View on GitHub`;
- `Report an Issue`;
- `MIT License`.

The About update is visually independent from the Max preset and does not
change its behavior or safety model.

## Non-goals

- No temperature curves or automatic temperature-based Max activation.
- No configurable Max percentage.
- No confirmation dialog or hold-to-activate interaction.
- No change to reported fan limits or arbitrary SMC writes.
- No persistence or automatic restoration of Max after launch, reconnect, or
  wake.
