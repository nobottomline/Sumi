import UIKit

// SheetAction — one row inside a SumiSheet.
//
// Model object, not a view. The presentation layer materialises
// a `SheetActionRow` for each one with the appropriate visual
// style. Per-action `handler` fires on tap right before the
// sheet dismisses; the `SumiSheet.present(...)` async return
// also yields the picked action's index so callers can switch
// on result in a flat code path.

public struct SheetAction: Sendable {

    public enum Style: Sendable {
        case `default`     // normal weight, textPrimary
        case destructive   // semibold, danger red — irreversible ops
    }

    public let title: String
    public let subtitle: String?
    public let icon: UIImage?
    public let style: Style
    public let handler: (@MainActor @Sendable () -> Void)?

    public init(
        title: String,
        subtitle: String? = nil,
        icon: UIImage? = nil,
        style: Style = .default,
        handler: (@MainActor @Sendable () -> Void)? = nil
    ) {
        self.title = title
        self.subtitle = subtitle
        self.icon = icon
        self.style = style
        self.handler = handler
    }
}
