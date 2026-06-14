# Changelog

All notable changes to Sumi are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.1.0] - 2026-06-14

First public release.

### Added
- **Design tokens** (`Sumi` target) — a two-layer system: brand primitives
  (`Sumi.Brand.*`) under role-named semantic tokens for colour, typography,
  spacing, radius, shadow, and motion. Light-only, manga-ink palette.
- **`SumiAlert`** — modal decision dialog with an `async/await` API. Replaces
  `UIAlertController(.alert)`. One/two/three actions, `cancel` · `destructive` ·
  `primary` styles, toggle options, progress variant, and a `customContent`
  slot.
- **`SumiSheet`** — bottom action sheet with optional icon column, destructive
  style, and swipe-to-dismiss. Replaces `UIAlertController(.actionSheet)`.
- **`SumiToast`** — non-blocking transient overlay with a queue, swipe, styles,
  and an optional action.
- **`SumiDialog`** — Material-style dialog with text fields, inline async
  validation, form layout, and custom content slots.
- **`SumiMenu`** — tap-anchored popover with sections, search, toggles, sliders,
  badges, and submenus.
- **`SumiContextMenu`** — long-press preview + actions on a blurred backdrop.
- **`SumiPicker`** — single / multi / tri-state choice dialog with animated
  indicators.
- **`SumiStepper`** — hero-sized integer stepper card for dialog content slots.
- **`SumiTable`** — compact key → value table for embedding inside an alert or
  dialog.
- **`SumiMenuKit`** — shared infrastructure for the menu-family components.
- **Demo** — an interactive catalog app that exercises every variant of every
  component.
- **`RichText`** — lightweight inline markup (bold, links, `code`) shared by the
  components.

[Unreleased]: ../../compare/0.1.0...HEAD
[0.1.0]: ../../releases/tag/0.1.0
