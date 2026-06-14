import UIKit
import Sumi
import SumiMenuKit

// Menu — popover-style action menu anchored to a source view.
//
// Smart positioning:
//
//   Horizontal: looks at where the anchor sits on screen and
//   picks one of three alignments —
//     • Anchor right edge near screen right  → right-align
//       (menu's trailing matches anchor's trailing)
//     • Anchor left edge near screen left    → left-align
//       (menu's leading matches anchor's leading)
//     • Anchor's centre near screen centre   → centre-align
//       (menu's centreX matches anchor's centreX)
//   Then clamps so the menu never escapes safe area.
//
//   Vertical: prefers below the anchor, flips above when
//   menuHeight + padding doesn't fit between anchor's bottom
//   and the bottom safe area.
//
//   Animation anchor-point: matches the alignment so the
//   scale-in springs from the corner closest to the anchor.
//   E.g. top-right nav button → menu springs from its
//   top-right corner; centre tab button → springs from
//   top-centre; bottom-left button → springs from bottom-left.
//
// All computed in a single pure function for testability and
// to keep the side-effect surface (window subview + animation)
// dead simple.

public enum Menu {

    /// `dismissOnAction = false` keeps the menu open after a
    /// regular action fires — paired with `Toggle` and
    /// `Slider` rows, this gives you a mini settings panel.
    /// Toggle / slider rows are inherently sticky regardless
    /// of this flag (toggling one shouldn't kick you out of
    /// the menu mid-flow).
    @MainActor
    public static func present(
        from sourceView: UIView,
        actions: [MenuAction],
        dismissOnAction: Bool = true,
        searchable: Bool = false
    ) {
        present(
            from: sourceView,
            sections: [MenuSection(actions: actions)],
            dismissOnAction: dismissOnAction,
            searchable: searchable
        )
    }

    @MainActor
    public static func present(
        from sourceView: UIView,
        sections: [MenuSection],
        dismissOnAction: Bool = true,
        searchable: Bool = false
    ) {
        guard let window = sourceView.window else { return }
        let controller = MenuPresentationController(
            sections: sections,
            anchor: sourceView,
            dismissOnAction: dismissOnAction,
            searchable: searchable
        )
        controller.attach(to: window)
    }
}

// MARK: - Presentation controller

@MainActor
final class MenuPresentationController {

    private static var live: [MenuPresentationController] = []

    private let sections: [MenuSection]
    private weak var anchor: UIView?
    private let dimmer = UIView()
    private let wrapper: MenuShadowWrapper
    private let dismissOnAction: Bool
    /// Vertical side the menu opened on relative to the anchor.
    /// Captured once at initial attach so subsequent submenu
    /// resizes stay anchored to the same edge instead of
    /// auto-flipping each time content height changes (which
    /// made tall submenus jump above the anchor mid-navigation).
    private enum OpenSide { case below, above }
    private var openSide: OpenSide = .below
    /// Natural content height of the current page — remembered so a
    /// keyboard show/hide (or any re-fit) can re-position the menu
    /// without re-measuring its content.
    private var lastNaturalHeight: CGFloat = 0
    /// How much the on-screen keyboard currently covers from the
    /// bottom of the window. Subtracted from the menu's available
    /// height so a searchable menu's results stay above the keyboard.
    private var keyboardOverlap: CGFloat = 0

    init(sections: [MenuSection], anchor: UIView, dismissOnAction: Bool, searchable: Bool) {
        self.sections = sections
        self.anchor = anchor
        self.dismissOnAction = dismissOnAction
        let menu = MenuListView(sections: sections, isSearchable: searchable)
        self.wrapper = MenuShadowWrapper(menu: menu)
        menu.onActionPicked = { [weak self] in
            guard self?.dismissOnAction == true else { return }
            self?.dismiss()
        }
        // Resize the menu frame to match the natural content
        // size of whatever page we navigate to (submenu push,
        // or pop back to parent). The MenuListView fires this
        // callback right after rebuilding its content for a
        // new page, in sync with its own slide animation, so
        // the frame change and the slide play together.
        menu.onContentSizeShouldChange = { [weak self] newHeight in
            self?.lastNaturalHeight = newHeight
            self?.resizeMenu(toNaturalHeight: newHeight)
        }
    }

    func attach(to window: UIWindow) {
        guard let anchor = anchor else { return }
        Self.live.append(self)
        registerKeyboardObservers()

        dimmer.frame = window.bounds
        dimmer.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        dimmer.backgroundColor = UIColor.black.withAlphaComponent(0)
        window.addSubview(dimmer)
        let tap = UITapGestureRecognizer(target: self, action: #selector(dimmerTapped))
        dimmer.addGestureRecognizer(tap)

        // Ask MenuListView directly for its natural content
        // size at our target width. We can't use
        // `wrapper.systemLayoutSizeFitting(...)` here because
        // MenuListView's internal UIScrollView doesn't propagate
        // its content's height through the constraint chain
        // (UIScrollView's intrinsicContentSize is noIntrinsic),
        // so the wrapper-level fitting returns junk and the
        // height clamping below operates on bogus values.
        // 250pt — Apple's native context-menu width, also the
        // minimum used by every other modern iOS popover. Earlier
        // versions used 280pt; user feedback was the menu read
        // as "huge" against the source it anchors to. 250pt
        // matches iOS UIContextMenuInteraction.
        let menuSize = wrapper.menu.naturalContentSize(forWidth: 250)
        lastNaturalHeight = menuSize.height

        wrapper.translatesAutoresizingMaskIntoConstraints = true
        let layout = Self.computeMenuLayout(
            anchorFrame: anchor.convert(anchor.bounds, to: window),
            menuSize: menuSize,
            windowBounds: window.bounds,
            safeInsets: window.safeAreaInsets
        )
        // Remember side — anchor's Y in layer-anchor-point space
        // is 0 when menu sits below the trigger (springs from
        // top edge), 1 when above (springs from bottom edge).
        // Subsequent submenu resizes stay on this side.
        openSide = (layout.anchorPoint.y == 0.0) ? .below : .above
        wrapper.frame = layout.frame
        window.addSubview(wrapper)

        // Set the layer's anchorPoint to match the alignment
        // corner so the scale animation springs from the
        // anchor's direction. Changing anchorPoint shifts the
        // layer's position (it's defined as the point of the
        // bounds that aligns with `position`), so we re-set
        // frame afterwards to put it back where computed.
        wrapper.layer.anchorPoint = layout.anchorPoint
        wrapper.frame = layout.frame

        wrapper.sumi_enableDynamicType()

        wrapper.transform = CGAffineTransform(scaleX: 0.94, y: 0.94)
        wrapper.alpha = 0
        UIView.animate(
            withDuration: Sumi.Motion.standard,
            delay: 0,
            usingSpringWithDamping: 0.86,
            initialSpringVelocity: 0.3,
            options: [.allowUserInteraction]
        ) {
            self.dimmer.backgroundColor = UIColor.black.withAlphaComponent(0.10)
            self.wrapper.transform = .identity
            self.wrapper.alpha = 1
        }
        UISelectionFeedbackGenerator().selectionChanged()
    }

    // MARK: - Layout math

    struct Layout {
        let frame: CGRect
        let anchorPoint: CGPoint
    }

    static func computeMenuLayout(
        anchorFrame: CGRect,
        menuSize: CGSize,
        windowBounds: CGRect,
        safeInsets: UIEdgeInsets
    ) -> Layout {
        // Gap from the anchor — 12pt feels less cramped than
        // 8pt, matches iOS context menu visual breathing room.
        let anchorGap: CGFloat = 12
        // Safe-area soft padding — menu never sits right up
        // against the edge.
        let edgePad: CGFloat = Sumi.Spacing.l

        // ---- VERTICAL ----
        // The menu may use the FULL height between the safe-area
        // insets, not just the gap on one side of the anchor. We
        // still pick a side for the spring origin, but a tall menu
        // is allowed to extend past the anchor — overlapping it the
        // way iOS context menus do — and is then shifted to stay
        // fully on-screen. Internal scroll therefore only appears
        // when the content genuinely can't fit between the insets,
        // instead of whenever one side of the anchor is short.
        let topLimit = safeInsets.top + edgePad
        let bottomLimit = windowBounds.height - safeInsets.bottom - edgePad
        let fullAvailable = max(0, bottomLimit - topLimit)

        let roomBelow = bottomLimit - anchorFrame.maxY - anchorGap
        let roomAbove = anchorFrame.minY - anchorGap - topLimit

        // Prefer the side that fits the content outright; otherwise
        // open from the side with more room (the card will overlap
        // the anchor rather than shrink + scroll).
        let showBelow: Bool
        if menuSize.height <= roomBelow {
            showBelow = true
        } else if menuSize.height <= roomAbove {
            showBelow = false
        } else {
            showBelow = roomBelow >= roomAbove
        }

        let clampedHeight = min(menuSize.height, fullAvailable)

        // Desired position on the chosen side, then clamped so the
        // whole card stays inside [topLimit, bottomLimit].
        let desiredY = showBelow
            ? anchorFrame.maxY + anchorGap
            : anchorFrame.minY - clampedHeight - anchorGap
        let y = max(topLimit, min(desiredY, bottomLimit - clampedHeight))

        // ---- HORIZONTAL ----
        // Pick alignment based on which side of the screen the
        // anchor sits on:
        //   • Anchor in the right third → right-align
        //   • Anchor in the left third  → left-align
        //   • Anchor in the middle      → centre-align
        // "Third" thresholds use a tolerance around screen
        // centre so a button that's *almost* centred (e.g.
        // a wide bar button) still centres rather than
        // jittering between alignments.
        let centreToleranceX: CGFloat = 60
        let anchorCentreOffset = anchorFrame.midX - windowBounds.midX

        let xCoord: CGFloat
        let anchorX: CGFloat
        if abs(anchorCentreOffset) <= centreToleranceX {
            xCoord = anchorFrame.midX - menuSize.width / 2
            anchorX = 0.5
        } else if anchorCentreOffset > 0 {
            // Anchor on the right side
            xCoord = anchorFrame.maxX - menuSize.width
            anchorX = 1.0
        } else {
            // Anchor on the left side
            xCoord = anchorFrame.minX
            anchorX = 0.0
        }

        // Clamp so the menu never escapes the safe area.
        let minX = safeInsets.left + edgePad
        let maxX = windowBounds.width - safeInsets.right - edgePad - menuSize.width
        let clampedX: CGFloat = (maxX >= minX)
            ? max(minX, min(maxX, xCoord))
            : xCoord

        // Animation anchor's Y matches vertical placement.
        let anchorY: CGFloat = showBelow ? 0.0 : 1.0

        return Layout(
            frame: CGRect(x: clampedX, y: y, width: menuSize.width, height: clampedHeight),
            anchorPoint: CGPoint(x: anchorX, y: anchorY)
        )
    }

    /// Re-fits the wrapper to the menu's new content height.
    /// Stays on the side we opened from (`openSide`) — no
    /// auto-flip on submenu navigation. The frame change is
    /// applied without an explicit `UIView.animate` wrapper:
    /// `MenuListView.installCurrentPage` already runs its slide +
    /// stage-height changes inside a `UIView.animate` block, and
    /// invokes our `onContentSizeShouldChange` callback FROM
    /// INSIDE that block. UIKit's animation-context inheritance
    /// then captures `wrapper.frame = newFrame` into the same
    /// spring, so the inner page slide, the inner stage height
    /// change, and the outer wrapper resize all run on a single
    /// shared animation — same start time, same spring spec,
    /// same finish frame.
    ///
    /// Without this inheritance trick the controller would start
    /// its own `UIView.animate` a microsecond after the inner one,
    /// and even with identical parameters the offset produced a
    /// visible "wrapper grows, then content slides" sequence —
    /// reading as an abrupt rise of the popover.
    fileprivate func resizeMenu(toNaturalHeight naturalHeight: CGFloat) {
        guard let window = wrapper.window else { return }
        let currentFrame = wrapper.frame
        let safe = window.safeAreaInsets
        let edgePad = Sumi.Spacing.l

        // Full height between the safe-area insets, minus whatever
        // the keyboard currently covers. The menu grows to fit its
        // content and is shifted on-screen rather than capped to one
        // side of the anchor — so it only scrolls internally when the
        // content can't fit the visible area at all.
        let topLimit = safe.top + edgePad
        let bottomLimit = window.bounds.height - safe.bottom - edgePad - keyboardOverlap
        let fullAvailable = max(0, bottomLimit - topLimit)
        let clampedHeight = max(0, min(naturalHeight, fullAvailable))

        // Keep the fixed edge of the side we opened from, then clamp
        // the whole card inside [topLimit, bottomLimit].
        let desiredY: CGFloat
        switch openSide {
        case .below: desiredY = currentFrame.minY
        case .above: desiredY = currentFrame.maxY - clampedHeight
        }
        let newY = max(topLimit, min(desiredY, bottomLimit - clampedHeight))

        wrapper.frame = CGRect(
            x: currentFrame.minX,
            y: newY,
            width: currentFrame.width,
            height: clampedHeight
        )
    }

    @objc private func dimmerTapped() {
        dismiss()
    }

    // MARK: - Keyboard

    /// A searchable menu's field is the only thing that raises a
    /// keyboard. When it does, re-fit the menu above the keyboard so
    /// the results stay visible; when it dismisses, restore. Uses the
    /// keyboard's own duration + curve so both move as one.
    private func registerKeyboardObservers() {
        let center = NotificationCenter.default
        center.addObserver(self, selector: #selector(keyboardChanged(_:)),
                           name: UIResponder.keyboardWillShowNotification, object: nil)
        center.addObserver(self, selector: #selector(keyboardChanged(_:)),
                           name: UIResponder.keyboardWillChangeFrameNotification, object: nil)
        center.addObserver(self, selector: #selector(keyboardChanged(_:)),
                           name: UIResponder.keyboardWillHideNotification, object: nil)
    }

    @objc private func keyboardChanged(_ note: Notification) {
        guard let window = wrapper.window,
              let end = (note.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? NSValue)?.cgRectValue
        else { return }

        let isHiding = note.name == UIResponder.keyboardWillHideNotification
        // Keyboard top in window space → how much it steals from the
        // window bottom (0 when off-screen / hiding).
        let kbTopInWindow = window.convert(end, from: nil).minY
        keyboardOverlap = isHiding ? 0 : max(0, window.bounds.height - kbTopInWindow)

        let duration = (note.userInfo?[UIResponder.keyboardAnimationDurationUserInfoKey] as? Double) ?? 0.25
        let curveRaw = (note.userInfo?[UIResponder.keyboardAnimationCurveUserInfoKey] as? UInt) ?? 7
        UIView.animate(
            withDuration: duration,
            delay: 0,
            options: [UIView.AnimationOptions(rawValue: curveRaw << 16), .allowUserInteraction]
        ) {
            self.resizeMenu(toNaturalHeight: self.lastNaturalHeight)
        }
    }

    private func dismiss() {
        NotificationCenter.default.removeObserver(self)
        UIView.animate(
            withDuration: Sumi.Motion.fast,
            delay: 0,
            options: [.curveEaseIn, .allowUserInteraction]
        ) {
            self.dimmer.backgroundColor = .clear
            self.wrapper.transform = CGAffineTransform(scaleX: 0.94, y: 0.94)
            self.wrapper.alpha = 0
        } completion: { _ in
            self.wrapper.removeFromSuperview()
            self.dimmer.removeFromSuperview()
            Self.live.removeAll { $0 === self }
        }
    }
}
