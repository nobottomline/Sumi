import UIKit
import Sumi
import SumiMenuKit

// ContextMenu — long-press preview + actions list.
//
// Architecture:
//   • Snapshot the source view, scale it up, place it on a
//     blurred backdrop above content.
//   • Actions list appears below (or above, if no room) the
//     preview snapshot.
//   • Tap outside or on action dismisses with reverse animation.
//   • Optional `attach(to:)` helper installs a UILongPressGestureRecognizer
//     so callers don't reimplement gesture handling.
//
// Apple's `UIContextMenuInteraction` does most of this in
// iOS 13+, but it's coupled to specific views (Collection /
// Table cell, Button) and uses system styling. We want:
//   1. Custom backdrop (manga-friendly blur), not system grey.
//   2. Our own action-row look (matches MenuComponent /
//      AlertComponent).
//   3. Works with arbitrary `UIView` source (reader page
//      Image View, history-list custom cell, anything).

public enum ContextMenu {

    @MainActor
    public static func present(
        from sourceView: UIView,
        actions: [MenuAction]
    ) {
        present(from: sourceView, sections: [MenuSection(actions: actions)])
    }

    /// Sections-based overload. Use when the action list is
    /// long enough that visual grouping (with the menu's
    /// inter-section dividers) improves scanability — e.g. a
    /// message bubble with "Reply / Copy" + "Pin / Save" +
    /// "Delete" groups.
    @MainActor
    public static func present(
        from sourceView: UIView,
        sections: [MenuSection]
    ) {
        guard let window = sourceView.window else { return }
        let controller = ContextMenuPresentation(
            sections: sections,
            sourceView: sourceView
        )
        controller.attach(to: window)
    }

    /// Convenience installer: attach a long-press gesture
    /// that auto-presents `ContextMenu` over `sourceView`.
    /// Returns the gesture so callers can store / disable it.
    ///
    /// `minimumPressDuration` is set to 0.28 s — between
    /// Apple's `UIContextMenuInteraction` (~0.4 s) and a quick
    /// peek; feels responsive on manga reader pages where
    /// long-press is the primary interaction. The default
    /// `UILongPressGestureRecognizer.minimumPressDuration` of
    /// 0.5 s feels noticeably laggy here.
    @MainActor
    @discardableResult
    public static func attachLongPress(
        to sourceView: UIView,
        actionsProvider: @escaping @MainActor @Sendable () -> [MenuAction]
    ) -> UILongPressGestureRecognizer {
        attachLongPress(to: sourceView) {
            [MenuSection(actions: actionsProvider())]
        }
    }

    /// Sections-based variant. Use for action lists long
    /// enough to benefit from inter-section dividers (chat
    /// message bubbles with edit/share/delete groups, manga
    /// covers with reading/manage/remove groups, etc.).
    @MainActor
    @discardableResult
    public static func attachLongPress(
        to sourceView: UIView,
        sectionsProvider: @escaping @MainActor @Sendable () -> [MenuSection]
    ) -> UILongPressGestureRecognizer {
        let recognizer = UILongPressGestureRecognizer()
        recognizer.minimumPressDuration = 0.28
        recognizer.allowableMovement = 12
        let handler = LongPressHandler(source: sourceView, sectionsProvider: sectionsProvider)
        recognizer.addTarget(handler, action: #selector(LongPressHandler.fired(_:)))
        objc_setAssociatedObject(recognizer, &LongPressHandler.key, handler, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        sourceView.addGestureRecognizer(recognizer)
        return recognizer
    }
}

// MARK: - Long-press handler (associated object)
//
// Pure objc wrapper so the target/action selector works.
// Stored as associated object on the gesture recognizer so
// it lives exactly as long as the gesture does.

@MainActor
private final class LongPressHandler: NSObject {
    nonisolated(unsafe) static var key: UInt8 = 0
    weak var source: UIView?
    let sectionsProvider: @MainActor @Sendable () -> [MenuSection]

    init(source: UIView, sectionsProvider: @escaping @MainActor @Sendable () -> [MenuSection]) {
        self.source = source
        self.sectionsProvider = sectionsProvider
    }

    @objc func fired(_ recognizer: UILongPressGestureRecognizer) {
        guard recognizer.state == .began, let view = source else { return }
        ContextMenu.present(from: view, sections: sectionsProvider())
    }
}

// MARK: - Presentation controller

@MainActor
final class ContextMenuPresentation {

    // Strong-retain registry — same retain-bug fix used by
    // AlertPresentation / MenuPresentationController. Without
    // this the controller dies right after `attach()` returns
    // and gestures fire on a nil self, leaving the menu stuck
    // on screen.
    private static var live: [ContextMenuPresentation] = []

    private weak var sourceView: UIView?
    private let sections: [MenuSection]

    private let blurBackdrop = UIVisualEffectView(effect: nil)
    private let previewSnapshot: UIView
    private let previewContainer = UIView()
    private let wrapper: MenuShadowWrapper

    /// Preview's natural (untransformed) center in window
    /// coordinates after clamping. Stored so the dismiss
    /// animation can compute a transform that returns the
    /// preview to the source's actual rect — without this,
    /// when clamping shifts the preview away from the source
    /// (large source, edge-of-screen source on iPad), the
    /// dismiss collapses to clamped center, then the source
    /// snaps back into view at its real position, creating
    /// the "jump" the user reported.
    private var clampedPreviewCenter: CGPoint = .zero
    /// Preview's natural (untransformed) size — width and
    /// height post-clamp. Pair with `clampedPreviewCenter`
    /// to reconstruct the preview's resting frame.
    private var clampedPreviewSize: CGSize = .zero

    init(sections: [MenuSection], sourceView: UIView) {
        self.sections = sections
        self.sourceView = sourceView
        // Snapshot the source as it currently looks. The
        // `afterScreenUpdates: false` variant captures the
        // current rendering pass without forcing a relayout,
        // which is what we want for a "freeze frame" preview.
        if let snap = sourceView.snapshotView(afterScreenUpdates: false) {
            self.previewSnapshot = snap
        } else {
            // Fallback: empty placeholder. We could compute a
            // rasterised version of the source via
            // `drawHierarchy(in:afterScreenUpdates:)` but the
            // snapshot API succeeds for every realistic case.
            let placeholder = UIView()
            placeholder.backgroundColor = Sumi.Color.surfaceElevated
            self.previewSnapshot = placeholder
        }
        let menu = MenuListView(sections: sections)
        self.wrapper = MenuShadowWrapper(menu: menu)
        menu.onActionPicked = { [weak self] in self?.dismiss() }
    }

    func attach(to window: UIWindow) {
        guard let sourceView = sourceView else { return }
        Self.live.append(self)

        blurBackdrop.translatesAutoresizingMaskIntoConstraints = false
        window.addSubview(blurBackdrop)
        NSLayoutConstraint.activate([
            blurBackdrop.topAnchor.constraint(equalTo: window.topAnchor),
            blurBackdrop.bottomAnchor.constraint(equalTo: window.bottomAnchor),
            blurBackdrop.leadingAnchor.constraint(equalTo: window.leadingAnchor),
            blurBackdrop.trailingAnchor.constraint(equalTo: window.trailingAnchor)
        ])
        let dimTap = UITapGestureRecognizer(target: self, action: #selector(backdropTapped))
        blurBackdrop.addGestureRecognizer(dimTap)
        blurBackdrop.isUserInteractionEnabled = true

        let sourceFrame = sourceView.convert(sourceView.bounds, to: window)
        let safe = window.safeAreaInsets

        // Clamp preview size to the window's safe area so a
        // large source (an iPad library cell, a tall reader
        // page, a wide manga banner) doesn't render outside
        // the screen. Scale uniformly down — never up — so
        // small sources keep their natural appearance.
        //
        //   • maxWidth  — 92 % of safe-area width, leaves ~16pt
        //     of breathing room on each side.
        //   • maxHeight — 55 % of window height, ensures the
        //     menu has room to sit either side of the preview.
        //
        // The 1.06 lift-scale applied during the present
        // animation is factored into the cap so the LIFTED
        // preview also fits. Without that factoring, a preview
        // exactly at the cap would pop past safe area edges
        // mid-animation.
        let safeAreaWidth = window.bounds.width - safe.left - safe.right
        let maxPreviewWidth = safeAreaWidth * 0.92 / 1.06
        let maxPreviewHeight = window.bounds.height * 0.55 / 1.06
        let scaleX = maxPreviewWidth / sourceFrame.width
        let scaleY = maxPreviewHeight / sourceFrame.height
        let previewScale = min(1.0, scaleX, scaleY)
        let previewWidth = sourceFrame.width * previewScale
        let previewHeight = sourceFrame.height * previewScale

        // Preview container holds the snapshot with rounded
        // corners. Snapshot stretches to fill the container,
        // container is positioned at the source's rect (clamped
        // to safe area so a near-edge source doesn't overflow).
        previewContainer.translatesAutoresizingMaskIntoConstraints = false
        previewContainer.layer.cornerRadius = Sumi.Radius.card
        previewContainer.layer.cornerCurve = .continuous
        previewContainer.clipsToBounds = true
        previewContainer.layer.applySumiShadow(.modal)
        window.addSubview(previewContainer)

        previewSnapshot.translatesAutoresizingMaskIntoConstraints = false
        previewContainer.addSubview(previewSnapshot)
        NSLayoutConstraint.activate([
            previewSnapshot.topAnchor.constraint(equalTo: previewContainer.topAnchor),
            previewSnapshot.bottomAnchor.constraint(equalTo: previewContainer.bottomAnchor),
            previewSnapshot.leadingAnchor.constraint(equalTo: previewContainer.leadingAnchor),
            previewSnapshot.trailingAnchor.constraint(equalTo: previewContainer.trailingAnchor)
        ])

        // Position preview at source's center, then clamp the
        // center so the preview's edges stay within safe area
        // (accounting for the 1.06 lift-scale). A source near
        // the right edge of the screen would otherwise have its
        // preview straddle the edge.
        let halfLiftedW = previewWidth * 1.06 / 2
        let halfLiftedH = previewHeight * 1.06 / 2
        let clampedCenterX = max(
            safe.left + halfLiftedW,
            min(window.bounds.width - safe.right - halfLiftedW, sourceFrame.midX)
        )
        let clampedCenterY = max(
            safe.top + halfLiftedH,
            min(window.bounds.height - safe.bottom - halfLiftedH, sourceFrame.midY)
        )
        let centerXConstraint = previewContainer.centerXAnchor.constraint(
            equalTo: window.leadingAnchor,
            constant: clampedCenterX
        )
        let centerYConstraint = previewContainer.centerYAnchor.constraint(
            equalTo: window.topAnchor,
            constant: clampedCenterY
        )
        let widthConstraint = previewContainer.widthAnchor.constraint(equalToConstant: previewWidth)
        let heightConstraint = previewContainer.heightAnchor.constraint(equalToConstant: previewHeight)
        NSLayoutConstraint.activate([
            centerXConstraint,
            centerYConstraint,
            widthConstraint,
            heightConstraint
        ])

        // Recompute the clamped preview rect for menu
        // positioning below — we use this instead of the
        // raw `sourceFrame` so the menu hugs the actual
        // visible preview, not the off-screen source.
        let clampedPreviewMaxY = clampedCenterY + halfLiftedH
        let clampedPreviewMinY = clampedCenterY - halfLiftedH
        let clampedPreviewMidX = clampedCenterX

        // Hide the original while the preview is showing so
        // we don't see double. Restore on dismiss.
        sourceView.alpha = 0

        // Menu wrapper: position below preview by default, flip
        // above if no room.
        window.addSubview(wrapper)
        let menuFitting = wrapper.menu.naturalContentSize(forWidth: 250)

        // Explicit height + width constraints on the wrapper.
        // MenuListView's internal scrollView swallows the
        // intrinsic-size chain (UIScrollView reports
        // `noIntrinsicMetric` for both axes), so without these
        // explicit anchors the wrapper rendered at 0×0 — the
        // menu appeared invisible. The `Menu` controller dodges
        // this by setting `wrapper.frame` directly; ContextMenu
        // uses AutoLayout and needs the anchors spelled out.
        wrapper.widthAnchor.constraint(equalToConstant: min(menuFitting.width, 250)).isActive = true
        wrapper.heightAnchor.constraint(equalToConstant: menuFitting.height).isActive = true

        let belowBudget = window.bounds.height
            - clampedPreviewMaxY
            - safe.bottom
            - Sumi.Spacing.xl
        let showBelow = menuFitting.height + Sumi.Spacing.m <= belowBudget

        if showBelow {
            wrapper.topAnchor.constraint(
                equalTo: window.topAnchor,
                constant: clampedPreviewMaxY + Sumi.Spacing.m
            ).isActive = true
        } else {
            wrapper.bottomAnchor.constraint(
                equalTo: window.topAnchor,
                constant: clampedPreviewMinY - Sumi.Spacing.m
            ).isActive = true
        }
        // Horizontal positioning: centerX is the PREFERRED
        // anchor (matches the preview's centre), but the
        // leading / trailing safe-area guards are REQUIRED.
        // Lowering centerX's priority below required means
        // AutoLayout breaks the centring (and shifts the wrapper
        // sideways) rather than breaking the width constraint
        // when a tiny source near the screen edge can't host a
        // 250pt-wide menu at its centre. Previously all three
        // were required — for a near-edge source (e.g. a 56pt
        // avatar at x=44), the resolver dropped `widthAnchor`,
        // collapsing the menu to ~56pt wide. Icons survived
        // but text labels overflowed and got truncated, so the
        // menu rendered as "icons only" — broken-looking.
        let centerX = wrapper.centerXAnchor.constraint(
            equalTo: window.leadingAnchor, constant: clampedPreviewMidX
        )
        centerX.priority = .defaultHigh  // 750 — below required (1000)
        centerX.isActive = true
        wrapper.leadingAnchor.constraint(greaterThanOrEqualTo: window.leadingAnchor, constant: safe.left + Sumi.Spacing.l).isActive = true
        wrapper.trailingAnchor.constraint(lessThanOrEqualTo: window.trailingAnchor, constant: -(safe.right + Sumi.Spacing.l)).isActive = true

        // Persist for `dismiss()` — used to compute the
        // return-to-source transform.
        clampedPreviewCenter = CGPoint(x: clampedCenterX, y: clampedCenterY)
        clampedPreviewSize = CGSize(width: previewWidth, height: previewHeight)

        window.layoutIfNeeded()

        // Initial state: preview LOOKS LIKE THE SOURCE (same
        // visible rect). We achieve this by computing a
        // transform that translates + scales the preview's
        // natural rect (centered at `clampedPreviewCenter`,
        // sized `clampedPreviewSize`) onto `sourceFrame`. Then
        // the animation interpolates to `.identity` (preview at
        // its clamped position, no scale) plus a 1.06 lift —
        // making it look as if the source physically lifted off
        // the page and grew into the preview, even when the
        // preview's resting position differs from the source's.
        //
        // Before this change the preview snapped to its clamped
        // position INSTANTLY (transform = .identity) before the
        // 1.06 scale started, so any source far from the
        // preview's resting center "teleported" on present —
        // visible as a jump.
        previewContainer.transform = Self.transformMatchingRect(
            sourceFrame,
            naturalCenter: clampedPreviewCenter,
            naturalSize: clampedPreviewSize
        )
        wrapper.alpha = 0
        wrapper.transform = CGAffineTransform(translationX: 0, y: showBelow ? -12 : 12)
            .scaledBy(x: 0.94, y: 0.94)

        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        UIView.animate(
            withDuration: Sumi.Motion.slow,
            delay: 0,
            usingSpringWithDamping: 0.82,
            initialSpringVelocity: 0.2,
            options: [.allowUserInteraction]
        ) {
            self.blurBackdrop.effect = UIBlurEffect(style: .systemUltraThinMaterialDark)
            // Final transform — natural position with a 1.06
            // "lift" scale.
            self.previewContainer.transform = CGAffineTransform(scaleX: 1.06, y: 1.06)
            self.wrapper.transform = .identity
            self.wrapper.alpha = 1
        }
    }

    /// Build a `CGAffineTransform` that, applied to a view with
    /// natural (untransformed) frame centered at `naturalCenter`
    /// with size `naturalSize`, makes its visible frame match
    /// `targetRect`. Used to morph the preview between its
    /// "lifted clamped" rest position and the source's actual
    /// frame on screen — present-time animates from source to
    /// clamped; dismiss-time animates the reverse, so the source
    /// can reappear at its real position without a visible snap.
    private static func transformMatchingRect(
        _ targetRect: CGRect,
        naturalCenter: CGPoint,
        naturalSize: CGSize
    ) -> CGAffineTransform {
        guard naturalSize.width > 0, naturalSize.height > 0 else { return .identity }
        let scaleX = targetRect.width / naturalSize.width
        let scaleY = targetRect.height / naturalSize.height
        let dx = targetRect.midX - naturalCenter.x
        let dy = targetRect.midY - naturalCenter.y
        // Apply scale around the layer's center (anchorPoint
        // default 0.5, 0.5), then translate.
        return CGAffineTransform(translationX: dx, y: dy).scaledBy(x: scaleX, y: scaleY)
    }

    @objc private func backdropTapped() {
        dismiss()
    }

    private func dismiss() {
        // Animate the preview back to the SOURCE'S CURRENT
        // rect (not just to identity) so the completion-time
        // reveal of `sourceView` aligns pixel-for-pixel with
        // where the preview ended up. When the source has
        // moved (e.g. user scrolled the list under the menu)
        // or when the preview was clamped to a different
        // position than the source's actual rect, animating to
        // .identity would land the preview at its clamped rest
        // pose — and then `sourceView.alpha = 1` in completion
        // would pop the source back at its real position,
        // looking like the preview "jumped" before disappearing.
        //
        // Computing the return transform at dismiss-time (not
        // present-time) means a scrolled-source also gets the
        // correct destination.
        let returnTransform: CGAffineTransform
        if let sourceView = sourceView, let window = sourceView.window {
            let currentSourceFrame = sourceView.convert(sourceView.bounds, to: window)
            returnTransform = Self.transformMatchingRect(
                currentSourceFrame,
                naturalCenter: clampedPreviewCenter,
                naturalSize: clampedPreviewSize
            )
        } else {
            // Source went away (view torn down) — fall back to
            // a simple shrink. We can't return to a frame we
            // don't have.
            returnTransform = CGAffineTransform(scaleX: 0.94, y: 0.94)
        }

        UIView.animate(
            withDuration: Sumi.Motion.standard,
            delay: 0,
            usingSpringWithDamping: 0.92,
            initialSpringVelocity: 0,
            options: [.allowUserInteraction]
        ) {
            self.blurBackdrop.effect = nil
            self.previewContainer.transform = returnTransform
            self.wrapper.alpha = 0
            self.wrapper.transform = CGAffineTransform(scaleX: 0.94, y: 0.94)
        } completion: { _ in
            self.sourceView?.alpha = 1
            self.wrapper.removeFromSuperview()
            self.previewContainer.removeFromSuperview()
            self.blurBackdrop.removeFromSuperview()
            Self.live.removeAll { $0 === self }
        }
    }
}
