# Contributing to Sumi

Thanks for your interest in improving Sumi! It's a small, opinionated design
system, so contributions are very welcome — bug fixes, new variants of existing
components, documentation, and the occasional new component all help.

Please be kind and constructive in issues and pull requests. We assume good
faith and expect the same in return.

## Ways to contribute

- **Found a bug?** Search the [issues](../../issues) first; if it's new, open
  one. Include the iOS version, device/simulator, a screenshot or short clip,
  and the smallest snippet that reproduces it.
- **Have a fix?** Send a pull request that references the issue. Keep it focused
  — one fix per PR.
- **Want a feature or a new component?** Open an issue describing the problem
  first. Sumi is intentionally narrow; please wait for a thumbs-up before
  investing a lot of time, in case it doesn't fit the system's direction.
- **Docs, comments, examples** — always appreciated, no issue needed for small
  improvements.

## Getting set up

Sumi has **zero external dependencies**, so there's nothing to install.

```bash
# (fork first if you intend to open a pull request)
git clone https://github.com/nobottomline/Sumi.git
cd Sumi

# Build the library for the simulator:
xcodebuild build -scheme Sumi-Package -destination 'generic/platform=iOS Simulator'

# Open the interactive component catalog:
open Demo/Demo.xcodeproj   # then ⌘R
```

The **Demo** app is the primary way to review changes by eye — it exercises
every variant of every component. If your change is visual, open the Demo and
look at it there before sending a PR.

> The Demo signs with a per-contributor team. Copy the template once:
> `cp Demo/Config/Signing.xcconfig.example Demo/Config/Signing.xcconfig`, then
> set your Apple Developer Team in Xcode (only needed to run on a real device;
> the simulator builds without it).

## Conventions

A change is much more likely to be merged if it follows the patterns already in
the codebase:

- **Tokens, never literals.** Colours, fonts, spacing, radius, shadow, and
  motion come from `Sumi.Color.*`, `Sumi.Font.*`, `Sumi.Spacing.*`, etc. Don't
  introduce raw `UIColor(...)` / point sizes in a component — add or reuse a
  semantic token in the `Sumi` target instead.
- **One product per component.** Each component lives in its own SPM target
  (`SumiAlert`, `SumiSheet`, …) and depends only on the `Sumi` token target
  (plus `SumiMenuKit` for menu-family components). Don't add cross-component
  dependencies.
- **`Sumi*` naming.** Public, app-facing types stay coherent with the package
  name.
- **`async/await` for decisions.** Modal components return their result by being
  awaited rather than via completion handlers.
- **iOS 13 is the floor.** Don't reach for a newer API without an
  `if #available` gate **and** a graceful fallback that works on iOS 13 (e.g.
  the SF Symbol bounce effect is iOS 17+, so it has a Core Animation fallback).
- **Keep the build warning-clean.** No new warnings.
- **Light-only.** Sumi is intentionally light-only; please don't add a dark
  theme without discussing it first.

## Pull requests

- Keep PRs small and focused; describe what changed and why.
- For visual changes, include a **before/after screenshot** from the Demo.
- Make sure the package **and** the Demo still build (`xcodebuild build` for
  both, or just let CI check it).
- Update `CHANGELOG.md` under `## [Unreleased]` if the change is user-facing.

## Licence

By contributing, you agree that your contributions are licensed under the
project's [MIT licence](LICENSE).
