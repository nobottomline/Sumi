# About Sumi — how & why

## Origin

Sumi did not start life as a standalone library. It began as the **in-house
design system of a production iOS app** — built under real shipping
constraints, not as a weekend experiment. Every component earned its place by
solving a concrete problem in that app before it was ever generalized.

It was also built **single-handedly**: one developer, both the design system
and the ambitious app it lives in. That app is large and unusually demanding
for a one-person project, and Sumi had to hold up across its entire surface —
every confirmation, every picker, every sheet and menu. There was no design
team to hand a spec to and no component library to buy; the system had to be
invented as the app needed it, then kept coherent as the app grew.

That heritage is the point. Each piece has been exercised against real user
flows — destructive confirmations, multi-select pickers, transient
notifications, long action sheets, awkward edge-case layouts — rather than
designed in the abstract. When the system had proven itself, it was extracted,
made self-contained, and opened up.

## Why build a design system at all

The stock UIKit chrome — `UIAlertController`, action sheets, system context
menus — is functional, but it works against you the moment you care about
polish:

- **Visually generic.** It looks like every other app; there is no room for a
  brand voice.
- **Hard to theme.** Colour, typography, and motion are largely out of your
  hands.
- **Completion-handler APIs.** `present(_:animated:completion:)` plus per-button
  handlers fragment a simple decision into callbacks.
- **Inconsistent across surfaces.** Alerts, sheets, and menus each follow their
  own rules; making them feel like one language is your job, repeated in every
  feature.

Sumi replaces that surface with one coherent, brandable, `async/await`-first
set of components, so a decision moment is a single line that reads
top-to-bottom:

```swift
let pick = await Alert.present(
    title: "Delete item?",
    message: "This can't be undone.",
    actions: [.init(title: "Cancel", style: .cancel),
              .init(title: "Delete", style: .destructive)]
)
```

## The aesthetic — why "Sumi"

墨 — *sumi*, the ink used in manga line-art. The whole system is built on one
image: **paper, ink, and a red hanko-stamp seal.** Surfaces are washi-paper
cream, text is sumi-ink near-black, accents borrow the vermillion of a
calligrapher's seal. It is intentionally **light-only** — the cream surface
*is* the identity, and a theme-wide dark mode would dilute it.

This is not decoration for its own sake. A single, opinionated visual idea is
what keeps a dozen separate components feeling like one family instead of a
pile of widgets.

## How it's built

- **Two-layer tokens.** Raw brand primitives (`Sumi.Brand.*`, named after the
  materials they evoke — `kamiCanvas`, `sumiInk`, `shuVermillion`) sit beneath
  role-named semantic tokens (`Sumi.Color.*`, `Sumi.Font.*`, `Sumi.Shadow.*`,
  …). Components only ever touch the semantic layer, so a repaint changes one
  file, never the call sites.
- **One product per component.** Each component ships as its own SPM product
  (`SumiAlert`, `SumiSheet`, `SumiToast`, …) on top of the shared `Sumi` token
  target. Importing `SumiAlert` pulls in the alert and nothing else.
- **UIKit, deliberately.** Presentation, animation, gesture handling, and the
  blurred backdrops needed precise control that is cleaner to express directly
  in UIKit than to fight a declarative layer for. The public surface stays
  small and modern — `async/await`, value-type configuration.
- **`async/await` wherever a user makes a choice.** Modal components return
  their result by being awaited, so flow control never scatters into handler
  closures.

## From in-house to open source

Once the components had earned their keep, the system was lifted out of its
origin app:

- **Renamed to stand on its own.** Inside the app, every component carried
  that app's name as its prefix — the alert was `⟨App⟩Alert`, the bottom sheet
  `⟨App⟩Sheet`, and so on. On extraction they were all renamed to the neutral
  `Sumi*` prefix (`SumiAlert`, `SumiSheet`, …), so the library reads as its own
  product rather than one app's private toolkit.
- **Made self-contained** — zero runtime dependencies for consumers, so it
  drops cleanly into any project's package graph.
- **Paired with the Demo app** — an interactive catalog that exercises every
  variant of every component in isolation, with no host app required. The Demo
  is how the library is reviewed by eye and how regressions get caught.
- **Released under the MIT licence.**

The origin app still consumes Sumi exactly the way any other project would —
as a Swift package pinned by path. That keeps the library honest: if an API is
awkward for an outside consumer, it is just as awkward for the app it came
from, and gets fixed in one place for everyone.

## Author

Sumi is designed and built by **Great Love**
([@nobottomline](https://github.com/nobottomline)) — the same single developer
behind the app it grew out of. Issues and pull requests are welcome.
