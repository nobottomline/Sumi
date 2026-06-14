import Foundation

// MenuSection — logical group of MenuActions with an optional
// small uppercase header.
//
// Solves the "wall of actions" problem: a library row menu
// with 8 entries reads as a long undifferentiated list. With
// sections we get something like:
//
//   READING
//     ▸ Mark all as read
//     ▸ Reset reading progress
//
//   MANAGE
//     ▸ Edit categories
//     ▸ Move to category…
//     ▸ Remove from library  (destructive)
//
//   SHARE
//     ▸ Share link
//
// UIMenu's `.menu` sub-element collapses into a separator-only
// look; ours keeps the header visible and inline, which scans
// MUCH faster.

public struct MenuSection: Sendable {

    /// Small uppercase header above the section, or `nil` to
    /// render the section unlabelled (still gets a thicker
    /// separator above it).
    public let title: String?
    public let actions: [MenuAction]

    public init(title: String? = nil, actions: [MenuAction]) {
        self.title = title
        self.actions = actions
    }
}
