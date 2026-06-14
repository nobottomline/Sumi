import Foundation

// TriState — three-state toggle used by tri-state ChoiceDialog.
//
// A classic use case is a chapter / item filter:
//
//   • .off       — "show all" / no constraint
//   • .on        — "only matching" (e.g. unread only)
//   • .negated   — "only NOT matching" (e.g. read only)
//
// Tapping a row cycles forward: .off → .on → .negated → .off.
// Renders three distinct indicators so the user can tell at
// a glance which constraint is active and in which direction.

public enum TriState: Sendable {
    case off
    case on
    case negated

    public var cyclingNext: TriState {
        switch self {
        case .off:     return .on
        case .on:      return .negated
        case .negated: return .off
        }
    }
}
