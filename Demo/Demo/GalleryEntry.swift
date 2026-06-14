import UIKit

// GalleryEntry — registration shape every component implements
// to surface inside the Sumi catalog.
//
// New components declare a static `entry` and the catalog list
// picks them up automatically. The App layer's
// `RootViewController` reflects over the registry without
// knowing component internals, so adding the next component
// (Alert, Sheet, ContextMenu…) requires zero edits to App/.
//
// Each entry returns a `UIViewController` that's the playground
// for that component — buttons to trigger, props to tweak,
// permutations to compare. That VC is responsible for the
// component's full design-time surface; the catalog only owns
// the list and navigation.

public struct GalleryEntry: Identifiable, Sendable {
    public let id: String
    public let title: String
    public let subtitle: String
    public let symbol: String
    public let make: @MainActor @Sendable () -> UIViewController

    public init(
        id: String,
        title: String,
        subtitle: String,
        symbol: String,
        make: @escaping @MainActor @Sendable () -> UIViewController
    ) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.symbol = symbol
        self.make = make
    }
}
