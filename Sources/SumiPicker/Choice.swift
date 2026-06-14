import UIKit

// Choice — a single option inside a ChoiceDialog.
//
// Carries everything the row needs to render: the underlying
// value (used for selection identity), a title + optional
// subtitle, plus three visual accessory slots that customise
// the leading area depending on the dialog flavour:
//
//   • `colorSwatch` — replaces the radio/check indicator with
//     a coloured circle. Used for theme / accent pickers
//     where the colour IS the choice.
//   • `previewImage` — small thumbnail next to the title,
//     for picking from visual variants (cover style, view
//     mode preview).
//   • `badge` — small accent pill (NEW / PRO / count) on the
//     trailing edge, same look as MenuAction's badge.
//
// `value` must be Hashable + Sendable because the dialog
// returns selections via async/await across actor boundaries.

public struct Choice<T: Hashable & Sendable>: Sendable {

    public let value: T
    public let title: String
    public let subtitle: String?
    public let badge: String?
    public let colorSwatch: ColorRef?
    public let previewImage: UIImage?
    /// When true, the choice is rendered greyed-out and
    /// non-interactive. The dialog skips selecting it.
    public let isDisabled: Bool

    public init(
        value: T,
        title: String,
        subtitle: String? = nil,
        badge: String? = nil,
        colorSwatch: UIColor? = nil,
        previewImage: UIImage? = nil,
        isDisabled: Bool = false
    ) {
        self.value = value
        self.title = title
        self.subtitle = subtitle
        self.badge = badge
        self.colorSwatch = colorSwatch.map(ColorRef.init)
        self.previewImage = previewImage
        self.isDisabled = isDisabled
    }
}

// MARK: - Sendable color wrapper
//
// UIColor isn't Sendable. We need a small wrapper so the
// Choice struct can be Sendable. `ColorRef` only holds a
// concrete static UIColor at construction time (any
// dynamic-provider colour is captured by value), so it's
// safe to pass across actors.

public struct ColorRef: @unchecked Sendable {
    public let color: UIColor
    public init(_ color: UIColor) {
        self.color = color
    }
}
