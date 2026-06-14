import UIKit

// SumiSheet — bottom action sheet.
//
// Modern replacement for `UIAlertController(preferredStyle:
// .actionSheet)`. The system version can't take SF Symbol icons,
// can't put a leading colour swatch on a row, can't have a
// subtitle, can't be swiped down — and it looks like 2015.
//
// Usage:
//
//   ```swift
//   let pick = await SumiSheet.present(
//       title: "Chapter options",
//       message: nil,
//       actions: [
//           .init(title: "Mark as read", icon: UIImage(systemName: "checkmark.circle")),
//           .init(title: "Download", icon: UIImage(systemName: "arrow.down.circle")),
//           .init(title: "Delete", icon: UIImage(systemName: "trash"), style: .destructive)
//       ]
//   )
//   ```
//
// Visual structure (top to bottom):
//
//   ┌─────────────────┐
//   │      ▔▔▔        │  drag handle (5×36 pill)
//   │  Optional title │
//   │  Optional msg   │
//   ├─────────────────┤
//   │  Action 1       │
//   ├─────────────────┤
//   │  Action 2       │
//   ├─────────────────┤
//   │  Destructive    │  (danger red)
//   └─────────────────┘
//      8pt gap (Apple-style separation)
//   ┌─────────────────┐
//   │     Cancel      │  separate card if cancelTitle != nil
//   └─────────────────┘
//      safe-area
//
// Icon column policy:
//   • If ANY action has an icon → reserve a 28pt leading icon
//     column on EVERY row + left-align titles (icon-led pattern).
//   • If NO action has an icon → titles centered (Apple pattern).
//
// Dismissal:
//   • Tap an action → handler fires + sheet dismisses, returns
//     that action's index.
//   • Tap dimmer / Cancel / swipe-down past threshold → returns
//     nil.

public enum SumiSheet {

    /// Presents a bottom action sheet. Returns the picked
    /// action's index in `actions`, or `nil` if the user
    /// cancelled (tapped dimmer / Cancel / swiped down).
    @MainActor
    @discardableResult
    public static func present(
        title: String? = nil,
        message: String? = nil,
        actions: [SheetAction],
        cancelTitle: String? = "Cancel"
    ) async -> Int? {
        await withCheckedContinuation { continuation in
            guard let window = Self.activeWindow() else {
                continuation.resume(returning: nil)
                return
            }
            let mainCard = SheetCard(title: title, message: message, actions: actions)
            let cancelCard = cancelTitle.map { SheetCancelCard(title: $0) }
            let presentation = SheetPresentation(
                mainCard: mainCard,
                cancelCard: cancelCard,
                actions: actions
            ) { pickedIndex in
                continuation.resume(returning: pickedIndex)
            }
            presentation.attach(to: window)
        }
    }

    /// Horizontal variant — actions laid out as icon-pills
    /// (icon over short label) in a scrollable row instead of
    /// a vertical list.
    ///
    /// Use when:
    ///   • Actions are best recognised by their icons (Share,
    ///     Copy, Save, Forward — verbs that map to a single
    ///     glyph).
    ///   • Labels stay short (≤ 1 word, ≤ 8 characters).
    ///   • The set is roughly fixed-size (4-8 actions); for
    ///     long lists the vertical sheet still wins because
    ///     horizontal scrolling reads worse on the touch
    ///     dimension users least expect.
    ///
    /// Same API contract as `present(...)` — returns the
    /// picked index or `nil` for cancel.
    /// Horizontal variant — actions laid out as icon-pills
    /// (icon over short label) in a row instead of a vertical
    /// list.
    ///
    /// `scrollable` controls overflow handling:
    ///
    ///   • `true` (default) — pill row wraps in a UIScrollView,
    ///     long lists scroll horizontally. Use when the action
    ///     count is dynamic or might exceed phone width (~5
    ///     pills fit before clipping).
    ///   • `false` — fixed layout, pills centred on the card
    ///     with their natural widths. Use when you KNOW you
    ///     have 3-4 pills that fit comfortably; avoids the
    ///     "phantom scroll indicator" hint and reads as a
    ///     committed-to-size layout.
    @MainActor
    @discardableResult
    public static func presentHorizontal(
        title: String? = nil,
        message: String? = nil,
        actions: [SheetAction],
        cancelTitle: String? = "Cancel",
        scrollable: Bool = true
    ) async -> Int? {
        await withCheckedContinuation { continuation in
            guard let window = Self.activeWindow() else {
                continuation.resume(returning: nil)
                return
            }
            let mainCard = SheetHorizontalCard(
                title: title,
                message: message,
                actions: actions,
                scrollable: scrollable
            )
            let cancelCard = cancelTitle.map { SheetCancelCard(title: $0) }
            let presentation = SheetPresentation(
                mainCard: mainCard,
                cancelCard: cancelCard,
                actions: actions
            ) { pickedIndex in
                continuation.resume(returning: pickedIndex)
            }
            presentation.attach(to: window)
        }
    }

    @MainActor
    private static func activeWindow() -> UIWindow? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }?
            .windows
            .first(where: \.isKeyWindow)
    }
}
