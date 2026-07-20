# Codex Quota Widget Design

## Goal

Ship one polished Codex-only macOS desktop widget that preserves quota-float's expanded QuotaCard hierarchy while adapting correctly when Codex exposes one or two base quota windows.

## Product boundary

- The widget displays Codex subscription quota only.
- Spark/model-specific limits are excluded.
- The menu bar, provider menu, token-cost history, and other provider widgets remain unchanged.
- One widget instance may pin one Codex account.
- A single available account requires no configuration. Multiple accounts are selectable in the widget configuration UI.

## Data contract

The main app writes Codex accounts into the existing widget snapshot. Each account contains:

- an opaque stable local identifier derived from the account's stable identity;
- a masked display label and optional plan name;
- an availability state;
- an ordered array of base quota metrics.

Each quota metric contains a stable id, display label, window duration when known, used percent, reset date, and explicit priority. The builder excludes Spark fields, removes invalid duplicates, and sorts by known duration ascending with stable source-order fallback.

The view never searches for `5h`, `7d`, `primary`, or `secondary`. It renders `metrics[0]` as the hero and `metrics[1]` as the secondary metric. If the 5-hour window disappears, the weekly metric naturally becomes the hero. If it returns, duration ordering restores it to the first slot.

## Account selection

- No configured id and exactly one account: use that account.
- No configured id and multiple accounts: show a configuration-required state.
- Configured id present: render only the matching account.
- Configured id missing: show `Account unavailable`; never switch silently.
- Picker labels use masked email plus plan. Raw credentials and raw auth paths never enter the snapshot.

## Visual hierarchy

The reference is quota-float's expanded QuotaCard, not QuotaOrb.

- Small: compact identity header, primary remaining percentage, glowing remaining bar, reset time.
- Medium: small content plus a clearly separated secondary metric or freshness footer.
- Large: near-reference hierarchy with plan/account identity, large hero, reset line, secondary metric, Codex mark, and freshness metadata.

All families use the same light card, static tier aurora, dark ink, remaining-percent semantics, tabular numbers, and explicit content padding. WidgetKit owns vibrant/accented rendering through `containerBackground`.

Risk tiers follow quota-float's remaining-percent semantics:

- healthy: remaining at least 50%;
- caution: remaining from 10% through 49%;
- critical: remaining below 10%.

The status light is separate from quota risk: green for fresh account data, gray for stale data, and orange-red for unavailable/corrupt data.

## Empty and failure states

- Missing snapshot: ask the user to open Token King.
- Corrupt snapshot: show a compact data-unavailable state.
- Stale snapshot: keep the last values visible with a stale indicator.
- No Codex account: show `Connect Codex in Token King`.
- Multiple accounts without a selection: show `Select a Codex account`.
- Selected account removed: show `Account unavailable`.
- Account without a valid metric: show `Quota unavailable`; never invent a percentage.

## Compatibility

New snapshot fields are optional so an older snapshot remains decodable. The schema version remains 1 because the change is additive. Existing generic provider snapshot fields remain available for deferred widgets.

## Acceptance criteria

- One Codex widget appears in the widget gallery and supports Small, Medium, and Large.
- Single-account users can add it without configuration.
- Two-account users can pin different accounts to different widget instances.
- A weekly-only response renders weekly as the hero.
- A 5-hour plus weekly response renders 5-hour first and weekly second.
- Spark limits never appear.
- Removing a selected account does not switch the widget to another account.
- Freshness status and quota tier use separate visual channels.
- Widget target builds and mapper/account-selection regression tests pass.
