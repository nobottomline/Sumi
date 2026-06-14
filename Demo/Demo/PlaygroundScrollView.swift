import UIKit

// PlaygroundScrollView — small UIScrollView subclass that
// fixes the "can't scroll if my finger lands on a button" bug.
//
// Why this exists:
//
//   `UIScrollView.touchesShouldCancel(in:)` returns `false` by
//   default when the touched subview is a `UIControl` — that's
//   Apple's choice for table cells, switches, sliders, where
//   tapping should "stick" without the scroll stealing. But in
//   our playgrounds the entire content is a column of
//   `PlaygroundButtonRow` (which IS a UIControl). With the
//   default behaviour, a user starting a vertical swipe with
//   their finger on a row can't scroll at all — the row claims
//   the touch and never yields. They have to start the swipe
//   in the gaps between rows.
//
// The override below returns `true` for ALL subviews: the
// scroll view always gets to cancel content touches when it
// detects a pan. UIScrollView's built-in delay (~150ms) still
// disambiguates tap-vs-drag: a quick tap fires the row's
// `.touchUpInside` like normal; a drag cancels the row's
// touch tracking and starts scrolling.
//
// Use everywhere a vertical button stack lives inside a scroll
// view. Drop-in replacement for `UIScrollView()`.

@MainActor
final class PlaygroundScrollView: UIScrollView {

    override func touchesShouldCancel(in view: UIView) -> Bool {
        // We intentionally don't filter by type — every kind of
        // content row in the playgrounds (PlaygroundButtonRow,
        // PlaygroundButtonRow's StatusLabel, custom rows) should
        // yield to scrolling.
        return true
    }
}
