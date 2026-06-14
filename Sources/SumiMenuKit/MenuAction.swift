import UIKit

// MenuAction — single row inside a menu / context-menu.
//
// Customisations over Apple's UIMenu / UIAction:
//
//   • `subtitle` — second line of copy under the title.
//   • `detail` — value text on the right edge (replaces icon
//     slot when set). For "Sort: Title" inline value display.
//   • `badge` — small pill on the right (NEW / PRO / "12"
//     unread count). UIMenu has nothing like this.
//   • `isSelected` — checkmark on the right, marks current
//     option in a single-choice group.
//   • `animateIconOnHighlight` — iOS 17+ SF Symbol bounce
//     effect when the row is hovered. Per-action opt-out for
//     icons where the motion would be distracting (e.g.
//     destructive actions, or actions like "Pause" where the
//     bounce visually conflicts with the icon's static meaning).
//     The animation also respects the system Reduce Motion
//     accessibility setting — no opt-in needed for that, it's
//     handled automatically.
//   • `style` — drives title tint (accent / danger / disabled).

public struct MenuAction: Sendable {

    public enum Style: Sendable {
        case `default`
        case destructive
        case disabled
    }

    public let title: String
    public let subtitle: String?
    public let detail: String?
    public let badge: String?
    public let systemImage: String?
    public let style: Style
    public let isSelected: Bool
    public let animateIconOnHighlight: Bool
    /// Android M3-style nested submenu. When non-nil, the row
    /// shows a chevron in its right slot (replacing any icon
    /// or detail), and tapping the row navigates the menu to
    /// these sections instead of firing `handler` and
    /// dismissing. The handler is silently ignored in that
    /// case — submenu rows are pure navigation triggers.
    public let submenu: [MenuSection]?
    /// Inline switch in the row's right slot. When set, the
    /// row tap toggles the switch and fires `onChange` — the
    /// menu does NOT dismiss (toggle rows are inherently
    /// "stay open" for fast multi-setting flows). UIMenu has
    /// no equivalent — toggles inside system menus require
    /// nesting into preferences.
    public let toggle: Toggle?
    /// Inline horizontal slider INSIDE the row. Row becomes
    /// taller (64pt) to fit slider below the title; current
    /// value is shown on the right. Drag the slider to adjust
    /// without leaving the menu. Pairs with `dismissOnAction:
    /// false` for live-tweak settings panels (brightness,
    /// page speed, audio volume) where a sheet would be too
    /// heavy.
    public let slider: Slider?
    public let handler: @MainActor @Sendable () -> Void

    public init(
        title: String,
        subtitle: String? = nil,
        detail: String? = nil,
        badge: String? = nil,
        systemImage: String? = nil,
        style: Style = .default,
        isSelected: Bool = false,
        animateIconOnHighlight: Bool = true,
        submenu: [MenuSection]? = nil,
        toggle: Toggle? = nil,
        slider: Slider? = nil,
        handler: @escaping @MainActor @Sendable () -> Void = {}
    ) {
        self.title = title
        self.subtitle = subtitle
        self.detail = detail
        self.badge = badge
        self.systemImage = systemImage
        self.style = style
        self.isSelected = isSelected
        self.animateIconOnHighlight = animateIconOnHighlight
        self.submenu = submenu
        self.toggle = toggle
        self.slider = slider
        self.handler = handler
    }

    // MARK: - Toggle

    public struct Toggle: Sendable {
        public let isOn: Bool
        public let onChange: @MainActor @Sendable (Bool) -> Void

        public init(isOn: Bool, onChange: @escaping @MainActor @Sendable (Bool) -> Void) {
            self.isOn = isOn
            self.onChange = onChange
        }
    }

    // MARK: - Slider

    public struct Slider: Sendable {
        public let value: Double
        public let range: ClosedRange<Double>
        /// Optional formatter for the inline value label
        /// shown on the right (e.g. "0.4s", "75%"). Defaults
        /// to one-decimal formatting.
        public let formatter: @MainActor @Sendable (Double) -> String
        /// Called continuously while user drags.
        public let onChange: @MainActor @Sendable (Double) -> Void

        public init(
            value: Double,
            range: ClosedRange<Double> = 0...1,
            formatter: @escaping @MainActor @Sendable (Double) -> String = { String(format: "%.1f", $0) },
            onChange: @escaping @MainActor @Sendable (Double) -> Void
        ) {
            self.value = value
            self.range = range
            self.formatter = formatter
            self.onChange = onChange
        }
    }
}
