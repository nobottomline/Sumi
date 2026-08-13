import UIKit

/// Controls whether a Sumi component participates in pointer interactions.
///
/// Pointer feedback is progressive enhancement: `.automatic` has no visible
/// effect until a mouse, trackpad, or compatible pointing device is present.
public enum SumiPointerBehavior: Sendable {
    /// Uses the system-appropriate pointer effect selected by the component.
    case automatic

    /// Suppresses pointer effects and component rollover visuals.
    case disabled

    public var isEnabled: Bool {
        self == .automatic
    }

    /// Returns `.automatic` only when both scopes permit pointer feedback.
    public func combined(with other: SumiPointerBehavior) -> SumiPointerBehavior {
        isEnabled && other.isEnabled ? .automatic : .disabled
    }
}

/// Semantic pointer effects shared by Sumi components.
///
/// Components choose an interaction intent instead of assembling raw
/// `UIPointerEffect` values. The implementation is unavailable at runtime on
/// iOS 13.0–13.3, where installation is a safe no-op.
public enum SumiPointerEffect: Sendable {
    /// Keeps the pointer visible and lets the component provide a restrained
    /// rollover appearance. Best for rows and full-width actions where scale
    /// or shadow would collide with neighbouring content.
    case hover

    /// Morphs the pointer into the control's rounded silhouette. Best for
    /// compact, transparent controls.
    case highlight

    /// Lifts an isolated opaque control above its surroundings.
    case lift
}

/// Installs a system pointer interaction while keeping pointer lifecycle and
/// component visuals separate.
///
/// Retain this object for as long as the receiving view is alive. The helper
/// intentionally does not retain the view.
@MainActor
public final class SumiPointerInteraction: NSObject {

    public typealias HoverHandler = @MainActor (_ isHovered: Bool) -> Void

    private weak var view: UIView?
    private let effect: SumiPointerEffect
    private let cornerRadius: CGFloat
    private let hoverHandler: HoverHandler
    private var installedInteraction: AnyObject?
    private var isHovered = false

    public var isEnabled: Bool = true {
        didSet {
            guard isEnabled != oldValue else { return }
            if #available(iOS 13.4, *) {
                (installedInteraction as? UIPointerInteraction)?.isEnabled = isEnabled
            }
            if !isEnabled {
                updateHovered(false)
            }
        }
    }

    public init(
        effect: SumiPointerEffect,
        cornerRadius: CGFloat,
        behavior: SumiPointerBehavior = .automatic,
        onHoverChanged: @escaping HoverHandler = { _ in }
    ) {
        self.effect = effect
        self.cornerRadius = cornerRadius
        self.hoverHandler = onHoverChanged
        super.init()
        isEnabled = behavior.isEnabled
    }

    /// Adds the interaction to `view`. Calling this method more than once
    /// moves the helper to the new view without stacking duplicate effects.
    public func install(on view: UIView) {
        if #available(iOS 13.4, *) {
            if let oldView = self.view,
               let oldInteraction = installedInteraction as? UIPointerInteraction {
                updateHovered(false)
                oldView.removeInteraction(oldInteraction)
            }
            let interaction = UIPointerInteraction(delegate: self)
            interaction.isEnabled = isEnabled
            view.addInteraction(interaction)
            self.view = view
            installedInteraction = interaction
        }
    }

    /// Re-evaluates the current region and style after component state or
    /// geometry changes.
    public func invalidate() {
        if #available(iOS 13.4, *) {
            (installedInteraction as? UIPointerInteraction)?.invalidate()
        }
    }

    private func updateHovered(_ hovered: Bool) {
        guard hovered != isHovered else { return }
        isHovered = hovered
        hoverHandler(hovered)
    }
}

@available(iOS 13.4, *)
extension SumiPointerInteraction: UIPointerInteractionDelegate {

    public func pointerInteraction(
        _ interaction: UIPointerInteraction,
        styleFor region: UIPointerRegion
    ) -> UIPointerStyle? {
        guard isEnabled, let view else { return nil }

        let parameters = UIPreviewParameters()
        parameters.visiblePath = UIBezierPath(
            roundedRect: view.bounds,
            cornerRadius: cornerRadius
        )
        let preview = UITargetedPreview(view: view, parameters: parameters)
        let pointerEffect: UIPointerEffect
        switch effect {
        case .hover:
            pointerEffect = .hover(
                preview,
                preferredTintMode: .none,
                prefersShadow: false,
                prefersScaledContent: false
            )
        case .highlight:
            pointerEffect = .highlight(preview)
        case .lift:
            pointerEffect = .lift(preview)
        }
        return UIPointerStyle(effect: pointerEffect)
    }

    public func pointerInteraction(
        _ interaction: UIPointerInteraction,
        willEnter region: UIPointerRegion,
        animator: UIPointerInteractionAnimating
    ) {
        updateHovered(true)
    }

    public func pointerInteraction(
        _ interaction: UIPointerInteraction,
        willExit region: UIPointerRegion,
        animator: UIPointerInteractionAnimating
    ) {
        updateHovered(false)
    }
}

@MainActor
public extension UIButton {
    /// Applies Sumi's pointer policy to a system button. UIKit supplies the
    /// appropriate pointer style; Sumi only controls participation.
    func sumi_applyPointerBehavior(_ behavior: SumiPointerBehavior = .automatic) {
        if #available(iOS 13.4, *) {
            isPointerInteractionEnabled = behavior.isEnabled
        }
    }
}
