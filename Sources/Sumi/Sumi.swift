import UIKit

// Sumi — a manga-inspired UIKit design system.
//
// Built on a single visual idea: manga is paper + ink + a red
// hanko-stamp seal. Every surface is washi-paper cream, every
// stroke is sumi-ink near-black, every accent borrows from the
// vermillion of a calligrapher's seal. The system is
// intentionally light-only — the cream surface IS the identity;
// a global dark mode would dilute it.
//
// Two-layer token model:
//
//   Brand layer  — `Sumi.Brand.*`. Raw palette primitives,
//                  named after the materials they evoke
//                  (`kamiCanvas`, `sumiInk`, `shuVermillion`).
//                  Consumers should rarely reach in here; the
//                  exception is when building a NEW component
//                  that doesn't have a semantic role yet.
//
//   Semantic     — `Sumi.Color.*`, `Sumi.Shadow.*`, `Sumi.Font.*`,
//                  `Sumi.Spacing.*`, etc. What every consumer
//                  reaches for. Names describe ROLE, not
//                  appearance, so a future repaint changes one
//                  layer without touching call sites.

public enum Sumi { }

// MARK: - Brand primitives
//
// The raw palette, named after manga's material vocabulary.
// Tokens are deliberately in Japanese so the lineage is
// obvious in code — and so extending the palette feels like a
// real decision, not a "let me add `accent2`" reflex.

public extension Sumi {

    enum Brand {

        // -- Surfaces (paper grades) --
        // `kamiCanvas` is the base washi-paper colour — warm
        // cream, slightly yellowed. `kamiPanel` sits above it
        // for elevated content (cards, sheets); it's a touch
        // warmer than pure white so it reads as "fresh paper on
        // old paper", not "white card on cream". `kamiSubtle`
        // is aged paper for recessed/inset surfaces.
        public static let kamiCanvas    = UIColor(red: 0.96, green: 0.94, blue: 0.89, alpha: 1) // 245,240,227
        public static let kamiPanel     = UIColor(red: 0.99, green: 0.98, blue: 0.96, alpha: 1) // 252,251,245
        public static let kamiSubtle    = UIColor(red: 0.93, green: 0.90, blue: 0.83, alpha: 1) // 237,229,212

        // -- Ink --
        // Cool-tinted near-black — the colour of sumi ink
        // settled on paper. We rarely render at full opacity
        // for body text (it reads too hard against cream);
        // semantic text tokens drop it to ~85% via alpha.
        public static let sumiInk       = UIColor(red: 0.15, green: 0.16, blue: 0.16, alpha: 1) // 38,41,41

        // -- Vermillion (hanko stamp) --
        // The brand accent. `shu` is the standard vermillion
        // used in calligrapher's seals — warm red with a touch
        // of orange. `shuDeeper` is the same family but darker,
        // reserved for irreversible / destructive operations so
        // they feel weighty against the standard accent.
        public static let shuVermillion = UIColor(red: 0.78, green: 0.29, blue: 0.18, alpha: 1) // 199,74,46
        public static let shuDeeper     = UIColor(red: 0.65, green: 0.21, blue: 0.12, alpha: 1) // 166,54,31

        // -- Functional supporters --
        // Drawn from the rest of the manga palette so success/
        // warning tokens stay tonally consonant with accent —
        // not Apple system green/yellow stuck onto manga paper.
        public static let takeBamboo    = UIColor(red: 0.29, green: 0.42, blue: 0.18, alpha: 1) // 74,107,46  — bamboo
        public static let yamabukiGold  = UIColor(red: 0.79, green: 0.48, blue: 0.06, alpha: 1) // 201,122,15 — yamabuki yellow

        // -- Warm shadow base --
        // Replaces neutral black for shadows. Umber is the tone
        // of ink that's bled slightly into the fibre — what a
        // shadow on real paper actually looks like.
        public static let umberShadow   = UIColor(red: 0.31, green: 0.20, blue: 0.08, alpha: 1) // 80,50,20
    }
}

// MARK: - Semantic colour tokens
//
// What components actually consume. Each token answers "what
// is this for" (intent, role), never "what colour is this"
// (literal value). Adding a token requires a real role — alias
// an existing one if the role is identical.

public extension Sumi {

    enum Color {

        // -- Surfaces --
        // Layered hierarchy: screen base → elevated content
        // (cards/sheets) → subtle insets (search bars, code
        // blocks). A layered surface-elevation system,
        // simplified to three rungs because anything more is a
        // taxonomy nobody remembers.
        public static let surface          = Brand.kamiCanvas
        public static let surfaceElevated  = Brand.kamiPanel
        public static let surfaceSubtle    = Brand.kamiSubtle

        // -- Text --
        // Three readability levels against any surface. Don't
        // reach for `Brand.sumiInk` directly in views; use these
        // so a future contrast bump cascades.
        public static let textPrimary      = Brand.sumiInk
        public static let textSecondary    = Brand.sumiInk.withAlphaComponent(0.55)
        public static let textTertiary     = Brand.sumiInk.withAlphaComponent(0.35)
        public static let textDisabled     = Brand.sumiInk.withAlphaComponent(0.25)

        // -- Brand action --
        // Anything tappable that affirms intent (Done, Save,
        // primary CTA, selected indicator). `onAccent` is the
        // foreground over accent backgrounds — cream rather
        // than pure white so it reads as "ink stamped on
        // paper", not "white text on a button".
        public static let accent           = Brand.shuVermillion
        public static let onAccent         = Brand.kamiCanvas

        // -- Borders / separators --
        // Ink at low alpha so they sit ON paper instead of
        // painting a hard hairline. `separator` is the row
        // divider; `borderHairline` is the card outline.
        public static let separator        = Brand.sumiInk.withAlphaComponent(0.10)
        public static let borderHairline   = Brand.sumiInk.withAlphaComponent(0.08)

        // -- Status --
        // `danger` is the same vermillion as `accent` —
        // deliberately ONE warm-red across the whole app.
        // Earlier this used `shuDeeper` for a "weightier"
        // destructive feel, but the deeper shade read as
        // muddy / brown next to the bright accent in dialogs
        // ("Delete" looked dark and dead rather than weighty).
        // We keep destructive-vs-affirmative distinction
        // through font weight + button position (destructive
        // is always last, bold), not through a separate hue.
        public static let danger           = Brand.shuVermillion
        public static let success          = Brand.takeBamboo
        public static let warning          = Brand.yamabukiGold

        // -- Modal scrim --
        // Tinted ink, not pure black — preserves the warm
        // tonality of the page underneath even at 45% alpha.
        public static let scrim            = Brand.sumiInk.withAlphaComponent(0.45)

        // -- Press feedback overlay --
        // Drop-in overlay for touch-down on tappable surfaces.
        // Inkwash effect: like brushing more pigment onto a
        // single spot. Lower alpha than a solid colour change
        // so it works on any surface.
        public static let pressOverlay     = Brand.sumiInk.withAlphaComponent(0.08)
    }
}

// MARK: - Shadows (elevation)
//
// Manga aesthetic uses WARM shadows — umber tones instead of
// neutral black. The visual effect is paper sitting on more
// paper, not glass on glass. Three rungs; consumers pick by
// elevation intent.

public extension Sumi {

    struct Shadow: Sendable {

        public let color: UIColor
        public let opacity: Float
        public let radius: CGFloat
        public let offset: CGSize

        /// Barely-there lift — chips, buttons, sticky headers.
        public static let subtle = Shadow(
            color: Brand.umberShadow,
            opacity: 0.10,
            radius: 3,
            offset: CGSize(width: 0, height: 1)
        )

        /// Cards, menus, popovers — visible but not heavy.
        public static let elevated = Shadow(
            color: Brand.umberShadow,
            opacity: 0.16,
            radius: 14,
            offset: CGSize(width: 0, height: 6)
        )

        /// Sheets, alerts, full-modal cards — clearly above
        /// the rest of the UI.
        public static let modal = Shadow(
            color: Brand.umberShadow,
            opacity: 0.22,
            radius: 28,
            offset: CGSize(width: 0, height: 14)
        )
    }
}

public extension CALayer {

    /// Applies a `Sumi.Shadow` in one call. Views that animate
    /// corners (e.g. menus that resize between frames) should
    /// also set `shadowPath` after layout — see `SumiMenu` for
    /// the pattern.
    func applySumiShadow(_ shadow: Sumi.Shadow) {
        shadowColor = shadow.color.cgColor
        shadowOpacity = shadow.opacity
        shadowRadius = shadow.radius
        shadowOffset = shadow.offset
    }
}

// MARK: - Spacing
//
// 8 pt baseline. Combine multipliers (`x2 = 16`) instead of
// typing literal padding into every view. The half-step (4 pt)
// is for inline gaps inside text-heavy containers only.

public extension Sumi {

    enum Spacing {
        public static let xxs: CGFloat  = 2
        public static let xs: CGFloat   = 4
        public static let s: CGFloat    = 8
        public static let m: CGFloat    = 12
        public static let l: CGFloat    = 16
        public static let xl: CGFloat   = 24
        public static let xxl: CGFloat  = 32
        public static let huge: CGFloat = 48
    }
}

// MARK: - Corner radius
//
// Buttons / inputs use `interactive` (10pt). Cards / sheets
// use `card` (16pt). System sheet morph radius is 12pt on
// iOS 16+ so `card` reads as "elevated above the sheet".

public extension Sumi {

    enum Radius {
        public static let interactive: CGFloat = 10
        public static let card: CGFloat        = 16
        public static let sheet: CGFloat       = 20
        public static let pill: CGFloat        = .infinity
    }
}

// MARK: - Typography
//
// Wrap UIFont's preferred-font API so each role has one
// canonical caller. The whole point of routing through
// `preferredFont(forTextStyle:)` is Dynamic Type integration —
// never set a fixed point size with `UIFont.withSize(_:)` since
// that strips the metrics; reach for `sumiSized(_:)` below when
// a component needs a tighter visual scale (e.g. 14pt body in
// alert messages) — it preserves Dynamic Type via UIFontMetrics.

public extension Sumi {

    enum Font {

        public static func display() -> UIFont {
            UIFont.preferredFont(forTextStyle: .largeTitle).withWeight(.bold)
        }
        public static func title() -> UIFont {
            UIFont.preferredFont(forTextStyle: .title2).withWeight(.semibold)
        }
        public static func heading() -> UIFont {
            UIFont.preferredFont(forTextStyle: .headline)
        }
        public static func body() -> UIFont {
            UIFont.preferredFont(forTextStyle: .body)
        }
        public static func bodyEmphasised() -> UIFont {
            UIFont.preferredFont(forTextStyle: .body).withWeight(.semibold)
        }
        public static func caption() -> UIFont {
            UIFont.preferredFont(forTextStyle: .footnote)
        }
        public static func captionEmphasised() -> UIFont {
            UIFont.preferredFont(forTextStyle: .footnote).withWeight(.semibold)
        }
    }
}

// MARK: - Motion
//
// Four-step duration ramp. Component authors pick by intent
// ("standard transition") not by milliseconds — keeps animation
// feel consistent across the app and lets us retune one rung
// without auditing every UIView.animate site.

public extension Sumi {

    enum Motion {
        public static let fast: TimeInterval     = 0.18  // press/release feedback
        public static let standard: TimeInterval = 0.28  // sheet rise / card fade
        public static let slow: TimeInterval     = 0.42  // hero transitions
        public static let long: TimeInterval     = 0.65  // illustrative animations

        /// True when the user has Reduce Motion enabled
        /// (Settings → Accessibility → Motion). Components
        /// MUST check this and replace decorative transform-
        /// based animations (slide, scale, parallax) with
        /// plain crossfades. Haptics, direct-manipulation
        /// gestures (finger-drag on a row, swipe-to-dismiss),
        /// and informative animations like a progress-bar
        /// drain stay UNTOUCHED — Reduce Motion applies to
        /// passive decorative motion only, not to user input
        /// feedback or time signals.
        ///
        /// `@MainActor` because `UIAccessibility` lives on the
        /// main actor — every existing call site is already
        /// in a `@MainActor` context (presentation classes),
        /// so the annotation is free.
        @MainActor
        public static var isReduced: Bool {
            UIAccessibility.isReduceMotionEnabled
        }
    }
}

// MARK: - Helpers

/// Module-internal — shared by `Sumi.Font.*` factories and the
/// `MarkdownRenderer` in `RichText.swift`. Not public: callers
/// outside Sumi should pick a `Sumi.Font.*` value rather than
/// reweight an arbitrary font.
internal extension UIFont {
    func withWeight(_ weight: UIFont.Weight) -> UIFont {
        let descriptor = fontDescriptor.addingAttributes([
            .traits: [UIFontDescriptor.TraitKey.weight: weight]
        ])
        return UIFont(descriptor: descriptor, size: 0)
    }
}

/// Returns a copy of the font at the requested point size, scaled
/// for Dynamic Type. The replacement for `UIFont.withSize(_:)` —
/// the built-in re-pegs to a fixed pt size and **strips** the
/// preferred-content-size metadata, so labels stop responding to
/// the user's Text Size setting.
///
/// `size` is the **default-category** baseline: at `.large`
/// content size the font renders at exactly `size`pt; at larger /
/// accessibility settings it scales proportionally through
/// `UIFontMetrics(forTextStyle: .body)` (the body ramp is the
/// closest match to Sumi's component hierarchy of 17 / 14 / 12).
///
/// Pair every call site with `adjustsFontForContentSizeCategory =
/// true` on its label so the font re-resolves when the user
/// changes Text Size at runtime — `scaledFont(for:)` only samples
/// the current category at construction time.
public extension UIFont {
    func sumiSized(_ size: CGFloat) -> UIFont {
        let base = UIFont(descriptor: fontDescriptor, size: size)
        return UIFontMetrics(forTextStyle: .body).scaledFont(for: base)
    }
}

/// Walks the view sub-tree and enables Dynamic-Type live-update
/// on every text-bearing view (label / textfield / textview /
/// button), then clamps the receiver to `maximumContentSizeCategory`
/// so accessibility-extra-large doesn't 3× the alert and explode
/// the layout. Call once after the hierarchy is assembled —
/// re-call only if subsequently-added subviews need it.
///
/// Why an explicit walk instead of a per-label property at each
/// call site: Sumi components have ~40 label constructions
/// scattered across Alert/Dialog/Toast/Table presentations.
/// One opt-in at the root view keeps the per-site boilerplate
/// down and ensures we never forget a label when adding new ones.
@MainActor
public extension UIView {
    func sumi_enableDynamicType(
        max: UIContentSizeCategory = .accessibilityLarge
    ) {
        applyDynamicTypeRecursively(self)
        if #available(iOS 15.0, *) {
            self.maximumContentSizeCategory = max
        }
    }
}

@MainActor
private func applyDynamicTypeRecursively(_ view: UIView) {
    switch view {
    case let l as UILabel:
        l.adjustsFontForContentSizeCategory = true
    case let tf as UITextField:
        tf.adjustsFontForContentSizeCategory = true
    case let tv as UITextView:
        tv.adjustsFontForContentSizeCategory = true
    case let b as UIButton:
        b.titleLabel?.adjustsFontForContentSizeCategory = true
    default:
        break
    }
    for sub in view.subviews {
        applyDynamicTypeRecursively(sub)
    }
}
