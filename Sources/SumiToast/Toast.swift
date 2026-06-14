import UIKit
import Sumi

// SumiToast — non-blocking transient overlay.
//
// Floating bottom-anchored card with semantic icon, progress
// countdown, optional action button, and three dismissal paths
// (tap, swipe, action). FIFO queue at window-scene level — so a
// burst of background events doesn't drown the user in stacked
// overlays.
//
// Visual identity (the bit that makes a toast feel premium):
//   • Backdrop is a `UIVisualEffectView` blur tinted toward kami
//     canvas so the toast reads as "manga paper floating above
//     content", not "iOS-blue glass slab".
//   • A 22pt semantic SF Symbol replaces the left accent bar —
//     it reads instantly ("error", "saved", "warning"), where a
//     coloured stripe needs the user to think.
//   • A 2pt progress bar drains linearly over the toast's
//     duration. Same motion language as native iOS Live Activity
//     timers: at zero, the toast leaves. No mystery countdown.
//   • Spring slide-up + 0.92→1 scale + soft overshoot. The pop
//     telegraphs "new event"; the overshoot stops just short of
//     bouncy.
//
// Interaction (matches Apple's `UINotificationFeedbackGenerator`
// rules and Material's snackbar timing):
//   • Tap card     → dismiss (action NOT fired).
//   • Tap action   → fire handler + dismiss.
//   • Swipe down   → dismiss.
//   • Auto         → dismiss when progress bar drains.
//
// Public API (all main-actor):
//   ```swift
//   Toast.show("Chapter 12 downloaded")
//   Toast.show("Translation failed",
//              style: .danger,
//              action: .init(title: "Retry") { ... })
//   Toast.show("Sync complete",
//              style: .success,
//              icon: UIImage(systemName: "checkmark.seal.fill"))
//   Toast.dismissAll(animated: true)
//   ```

@MainActor
public enum Toast {

    public struct Action: Sendable {
        public let title: String
        public let handler: @MainActor @Sendable () -> Void
        public init(title: String, handler: @escaping @MainActor @Sendable () -> Void) {
            self.title = title
            self.handler = handler
        }
    }

    public enum Style: Sendable {
        case info, success, warning, danger
    }

    /// Show a toast. `icon` overrides the style's default
    /// semantic SF Symbol if provided (rare — most callers just
    /// pass `style:`).
    ///
    /// `bottomInset` lifts the toast that many points above the
    /// window's bottom safe-area. Use when the host app has a
    /// custom bar (tab bar, ad bar, mini-player) sitting above
    /// the home indicator — `window.safeAreaLayoutGuide.bottom`
    /// only excludes the home-indicator strip, NOT a UITabBar
    /// (the bar is a content sibling, not part of the window
    /// safe area). Default 0 keeps behaviour unchanged for
    /// callers without a chrome bar.
    public static func show(
        _ message: String,
        style: Style = .info,
        icon: UIImage? = nil,
        action: Action? = nil,
        duration: TimeInterval? = nil,
        bottomInset: CGFloat = 0
    ) {
        let resolved = duration ?? Self.recommendedDuration(for: message, hasAction: action != nil)
        ToastCoordinator.shared.enqueue(
            ToastItem(
                message: message,
                style: style,
                icon: icon ?? Self.defaultIcon(for: style),
                action: action,
                duration: resolved,
                bottomInset: bottomInset
            )
        )
    }

    public static func dismissAll(animated: Bool = true) {
        ToastCoordinator.shared.dismissAll(animated: animated)
    }

    private static func recommendedDuration(for message: String, hasAction: Bool) -> TimeInterval {
        // Action toasts deserve a few extra seconds so the user
        // has time to react. Pure-info toasts can be terser.
        // Numbers come from Material's snackbar guidelines
        // (4–7 s for actionable, 2–4 s for fire-and-forget).
        let base: TimeInterval = hasAction ? 4.0 : 2.5
        let perChar: TimeInterval = 0.04
        let computed = base + Double(message.count) * perChar
        return min(max(computed, 2.0), 7.0)
    }

    private static func defaultIcon(for style: Style) -> UIImage? {
        switch style {
        case .info:    return UIImage(systemName: "info.circle.fill")
        case .success: return UIImage(systemName: "checkmark.circle.fill")
        case .warning: return UIImage(systemName: "exclamationmark.triangle.fill")
        case .danger:  return UIImage(systemName: "xmark.octagon.fill")
        }
    }
}

// MARK: - Toast item

private struct ToastItem {
    let message: String
    let style: Toast.Style
    let icon: UIImage?
    let action: Toast.Action?
    let duration: TimeInterval
    /// Additional bottom padding above the window's safe area.
    /// Lets the host app push the toast above a tab bar / mini-
    /// player / ad bar that the window's safeAreaLayoutGuide
    /// doesn't account for.
    let bottomInset: CGFloat
}

// MARK: - Coordinator

@MainActor
private final class ToastCoordinator {
    static let shared = ToastCoordinator()

    private var queue: [ToastItem] = []
    private var currentView: ToastView?
    private var currentItem: ToastItem?

    private init() {}

    func enqueue(_ item: ToastItem) {
        // Two queue policies based on whether the new toast is
        // actionable (a "snackbar" — UNDO/Retry/Open) or a
        // plain notification:
        //
        // • Plain toast: append. Burst of "Chapter 1/2/3 done"
        //   should ALL surface, so the user knows everything
        //   that happened.
        //
        // • Snackbar (has action): REPLACE any current snackbar,
        //   and drop other pending snackbars. Apple Mail
        //   pattern — only the most recent UNDO is meaningful;
        //   older operations are already committed and the user
        //   has demonstrably moved on. Stacking snackbars would
        //   be visual noise and only the last action is reachable.
        if item.action != nil {
            // Drop any queued snackbars that haven't shown yet —
            // their undo windows are pre-emptively closed by the
            // arrival of a newer one. Keep queued plain toasts.
            queue.removeAll { $0.action != nil }

            if let current = currentView, currentItem?.action != nil {
                // Current is a snackbar → dismiss it and present
                // the new one. The dismissed snackbar's action
                // is NOT fired (committed silently by virtue of
                // being replaced).
                queue.insert(item, at: 0)
                let toDismiss = current
                currentView = nil
                currentItem = nil
                toDismiss.dismiss(animated: true) { [weak self] in
                    self?.presentNext()
                }
                return
            }
        }
        queue.append(item)
        if currentView == nil {
            presentNext()
        }
    }

    func dismissAll(animated: Bool) {
        queue.removeAll()
        guard let toast = currentView else { return }
        currentView = nil
        currentItem = nil
        toast.dismiss(animated: animated) { [weak self] in
            self?.presentNext()
        }
    }

    private func presentNext() {
        guard let next = queue.first else { return }
        queue.removeFirst()
        guard let window = Self.activeWindow() else { return }

        let view = ToastView(item: next)
        view.onTapAction = { [weak self, action = next.action] in
            action?.handler()
            self?.advance(after: view)
        }
        view.onDismiss = { [weak self] in
            self?.advance(after: view)
        }
        // Auto-dismiss is now driven by the SAME UIView.animate
        // that drains the progress bar — its completion handler
        // fires `onProgressFinished`. Previous version ran a
        // parallel `Task.sleep(item.duration)`; the two timers
        // could drift 100–200 ms apart over 4 seconds (Task.sleep
        // is async-scheduler, UIView.animate is CADisplayLink/
        // GPU), leaving a visible "bar reached zero but the toast
        // hasn't started leaving yet" gap.
        view.onProgressFinished = { [weak self] in
            self?.advance(after: view)
        }
        currentView = view
        currentItem = next
        view.present(in: window, bottomInset: next.bottomInset)

        // Belt-and-braces fallback dismiss. UIView.animate's
        // completion handler is the primary trigger above, but
        // it skips when `finished == false` — which happens
        // whenever the animation is interrupted (window resize,
        // implicit layout change, main-thread block long enough
        // to invalidate the CADisplayLink tick, etc.). On
        // iPhones under memory pressure a 2 s+ runloop hang
        // can leave the animation in the "stuck completed
        // but completion never fired" limbo. This Task wakes
        // after `duration + 0.5 s` and force-advances if the
        // toast is still the active one. Idempotent — the
        // `currentView === view` guard inside `advance`
        // makes the call a no-op if the primary path already
        // dismissed.
        let dismissalDeadline = next.duration + 0.5
        Task { @MainActor [weak self, weak view] in
            try? await Task.sleep(nanoseconds: UInt64(dismissalDeadline * 1_000_000_000))
            guard let self, let view, self.currentView === view else { return }
            self.advance(after: view)
        }
    }

    private func advance(after view: ToastView) {
        guard currentView === view else { return }
        currentItem = nil
        currentView = nil
        view.dismiss(animated: true) { [weak self] in
            self?.presentNext()
        }
    }

    private static func activeWindow() -> UIWindow? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }?
            .windows
            .first(where: \.isKeyWindow)
            ?? UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }
                .first?
                .windows
                .first
    }
}

// MARK: - View
//
// Layered structure (outer → inner):
//
//   ToastView (no clip, owns shadow)
//   └── contentContainer (clip, rounded)
//       ├── blurView (UIVisualEffectView, fills)
//       ├── tintView (warm kami overlay, fills)
//       ├── borderView (1pt hairline border, fills)
//       ├── stack (icon + message + divider + action)
//       └── progressBar (frame-based, 2pt at bottom)
//
// The split between `ToastView` (no clip) and `contentContainer`
// (clip) is so the rounded card mask can clip the blur/tint
// cleanly while the parent's shadow still renders outside.

@MainActor
private final class ToastView: UIView {

    var onTapAction: (() -> Void)?
    var onDismiss: (() -> Void)?
    /// Fires when the progress bar's drain animation finishes
    /// naturally (i.e. `duration` seconds have elapsed). NOT
    /// called when the animation is interrupted by an
    /// out-of-band dismiss (gesture, tap, dismissAll).
    var onProgressFinished: (() -> Void)?

    private let item: ToastItem
    private let contentContainer = UIView()
    private let blurView = UIVisualEffectView(effect: UIBlurEffect(style: .systemUltraThinMaterial))
    private let tintView = UIView()
    private let borderView = UIView()
    private let iconView = UIImageView()
    private let messageLabel = UILabel()
    private let divider = UIView()
    private let actionButton = UIButton(type: .system)
    private let progressBar = UIView()
    private var bottomConstraint: NSLayoutConstraint?
    private var isProgressAnimating = false
    private var didLayout = false

    private static let cornerRadius: CGFloat = 14
    private static let progressBarHeight: CGFloat = 2

    init(item: ToastItem) {
        self.item = item
        super.init(frame: .zero)
        configure()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) not supported") }

    private func configure() {
        translatesAutoresizingMaskIntoConstraints = false
        backgroundColor = .clear
        // Shadow on the outer view so it draws around the
        // rounded silhouette (set as `shadowPath` in layoutSubviews
        // for a sharp shadow that follows the corners).
        layer.applySumiShadow(.elevated)
        clipsToBounds = false

        // Content container — clips to rounded corners so the
        // blur, tint, and progress bar all respect the card
        // shape.
        contentContainer.translatesAutoresizingMaskIntoConstraints = false
        contentContainer.backgroundColor = .clear
        contentContainer.layer.cornerRadius = Self.cornerRadius
        contentContainer.layer.cornerCurve = .continuous
        contentContainer.clipsToBounds = true
        addSubview(contentContainer)

        // Blur — `.systemUltraThinMaterial` adapts subtly to
        // surrounding content (cooler over photos, warmer over
        // canvas). Keeps the toast readable on any background.
        blurView.translatesAutoresizingMaskIntoConstraints = false
        contentContainer.addSubview(blurView)

        // Warm tint above the blur — drags the result back toward
        // kami canvas so the toast feels like part of Sumi's
        // manga palette, not generic iOS glass. Low alpha to
        // preserve the blur's adaptive quality.
        tintView.translatesAutoresizingMaskIntoConstraints = false
        tintView.backgroundColor = Sumi.Brand.kamiCanvas.withAlphaComponent(0.42)
        tintView.isUserInteractionEnabled = false
        contentContainer.addSubview(tintView)

        // Hairline border — defines the silhouette against
        // light backgrounds where the blur might disappear.
        borderView.translatesAutoresizingMaskIntoConstraints = false
        borderView.backgroundColor = .clear
        borderView.layer.cornerRadius = Self.cornerRadius
        borderView.layer.cornerCurve = .continuous
        borderView.layer.borderColor = Sumi.Color.borderHairline.cgColor
        borderView.layer.borderWidth = 1.0 / UIScreen.main.scale
        borderView.isUserInteractionEnabled = false
        contentContainer.addSubview(borderView)

        // Icon — semantic SF Symbol tinted to the style colour.
        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.image = item.icon
        iconView.tintColor = colorForStyle(item.style)
        iconView.contentMode = .scaleAspectFit
        iconView.preferredSymbolConfiguration = UIImage.SymbolConfiguration(
            pointSize: 20,
            weight: .semibold
        )
        contentContainer.addSubview(iconView)

        // Message.
        messageLabel.translatesAutoresizingMaskIntoConstraints = false
        messageLabel.text = item.message
        messageLabel.font = Sumi.Font.body().sumiSized(14)
        messageLabel.textColor = Sumi.Color.textPrimary
        // 3 lines: covers the rare verbose toast ("Translation
        // failed for chapter 7 due to network timeout — tap
        // Retry") without growing unbounded. Anything beyond 3
        // is a sign the message belongs in an Alert or Sheet,
        // not a transient toast.
        messageLabel.numberOfLines = 3
        messageLabel.lineBreakMode = .byTruncatingTail
        messageLabel.setContentHuggingPriority(.defaultLow, for: .horizontal)
        contentContainer.addSubview(messageLabel)

        // Action button + divider (only when action present).
        let hasAction = item.action != nil
        if hasAction, let action = item.action {
            divider.translatesAutoresizingMaskIntoConstraints = false
            divider.backgroundColor = Sumi.Color.borderHairline
            contentContainer.addSubview(divider)

            actionButton.translatesAutoresizingMaskIntoConstraints = false
            actionButton.setTitle(action.title, for: .normal)
            actionButton.titleLabel?.font = Sumi.Font.bodyEmphasised().sumiSized(14)
            actionButton.setTitleColor(colorForStyle(item.style), for: .normal)
            actionButton.setContentHuggingPriority(.required, for: .horizontal)
            actionButton.setContentCompressionResistancePriority(.required, for: .horizontal)
            actionButton.addTarget(self, action: #selector(actionTapped), for: .touchUpInside)
            // Generous touch padding for fat fingers.
            actionButton.contentEdgeInsets = UIEdgeInsets(top: 6, left: 4, bottom: 6, right: 4)
            contentContainer.addSubview(actionButton)
        }

        // Progress bar — frame-based subview pinned to bottom
        // edge of contentContainer. Frame is set in
        // `layoutSubviews` while not animating; animation
        // shrinks the bar's width to 0 over `item.duration`.
        progressBar.backgroundColor = colorForStyle(item.style).withAlphaComponent(0.75)
        contentContainer.addSubview(progressBar)

        // ---- Constraints ----
        let leading: CGFloat = 14
        let trailing: CGFloat = 14
        let vertical: CGFloat = 12

        NSLayoutConstraint.activate([
            contentContainer.topAnchor.constraint(equalTo: topAnchor),
            contentContainer.leadingAnchor.constraint(equalTo: leadingAnchor),
            contentContainer.trailingAnchor.constraint(equalTo: trailingAnchor),
            contentContainer.bottomAnchor.constraint(equalTo: bottomAnchor),

            blurView.topAnchor.constraint(equalTo: contentContainer.topAnchor),
            blurView.leadingAnchor.constraint(equalTo: contentContainer.leadingAnchor),
            blurView.trailingAnchor.constraint(equalTo: contentContainer.trailingAnchor),
            blurView.bottomAnchor.constraint(equalTo: contentContainer.bottomAnchor),

            tintView.topAnchor.constraint(equalTo: contentContainer.topAnchor),
            tintView.leadingAnchor.constraint(equalTo: contentContainer.leadingAnchor),
            tintView.trailingAnchor.constraint(equalTo: contentContainer.trailingAnchor),
            tintView.bottomAnchor.constraint(equalTo: contentContainer.bottomAnchor),

            borderView.topAnchor.constraint(equalTo: contentContainer.topAnchor),
            borderView.leadingAnchor.constraint(equalTo: contentContainer.leadingAnchor),
            borderView.trailingAnchor.constraint(equalTo: contentContainer.trailingAnchor),
            borderView.bottomAnchor.constraint(equalTo: contentContainer.bottomAnchor),

            iconView.leadingAnchor.constraint(equalTo: contentContainer.leadingAnchor, constant: leading),
            iconView.centerYAnchor.constraint(equalTo: contentContainer.centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 22),
            iconView.heightAnchor.constraint(equalToConstant: 22),

            messageLabel.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 10),
            messageLabel.topAnchor.constraint(equalTo: contentContainer.topAnchor, constant: vertical),
            messageLabel.bottomAnchor.constraint(equalTo: contentContainer.bottomAnchor, constant: -(vertical + Self.progressBarHeight))
        ])

        if hasAction {
            NSLayoutConstraint.activate([
                divider.widthAnchor.constraint(equalToConstant: 1.0 / UIScreen.main.scale),
                divider.heightAnchor.constraint(equalToConstant: 22),
                divider.centerYAnchor.constraint(equalTo: iconView.centerYAnchor),
                divider.trailingAnchor.constraint(equalTo: actionButton.leadingAnchor, constant: -10),

                actionButton.trailingAnchor.constraint(equalTo: contentContainer.trailingAnchor, constant: -(trailing - 4)),
                actionButton.centerYAnchor.constraint(equalTo: iconView.centerYAnchor),

                messageLabel.trailingAnchor.constraint(lessThanOrEqualTo: divider.leadingAnchor, constant: -10)
            ])
        } else {
            NSLayoutConstraint.activate([
                messageLabel.trailingAnchor.constraint(equalTo: contentContainer.trailingAnchor, constant: -trailing)
            ])
        }

        // Tap card to dismiss (excludes the action button which
        // has its own target).
        let tap = UITapGestureRecognizer(target: self, action: #selector(cardTapped))
        tap.cancelsTouchesInView = false
        contentContainer.addGestureRecognizer(tap)

        // Pan down to dismiss.
        let pan = UIPanGestureRecognizer(target: self, action: #selector(panned))
        addGestureRecognizer(pan)
    }

    private func colorForStyle(_ style: Toast.Style) -> UIColor {
        switch style {
        case .info:    return Sumi.Color.accent
        case .success: return Sumi.Color.success
        case .warning: return Sumi.Color.warning
        case .danger:  return Sumi.Color.danger
        }
    }

    // MARK: - Layout

    override func layoutSubviews() {
        super.layoutSubviews()
        // Sharp shadow that follows the rounded card outline.
        // Without `shadowPath`, the shadow is computed from the
        // rendered alpha mask, which is fine but noticeably
        // slower per frame.
        layer.shadowPath = UIBezierPath(
            roundedRect: bounds,
            cornerRadius: Self.cornerRadius
        ).cgPath

        if !isProgressAnimating {
            // Pin progress bar to bottom of content container,
            // full width, until the drain animation takes over.
            progressBar.frame = CGRect(
                x: 0,
                y: contentContainer.bounds.height - Self.progressBarHeight,
                width: contentContainer.bounds.width,
                height: Self.progressBarHeight
            )
        }
        didLayout = true
    }

    // MARK: - Presentation

    fileprivate func present(in window: UIWindow, bottomInset: CGFloat = 0) {
        window.addSubview(self)
        sumi_enableDynamicType()
        NSLayoutConstraint.activate([
            leadingAnchor.constraint(greaterThanOrEqualTo: window.leadingAnchor, constant: Sumi.Spacing.l),
            trailingAnchor.constraint(lessThanOrEqualTo: window.trailingAnchor, constant: -Sumi.Spacing.l),
            widthAnchor.constraint(lessThanOrEqualToConstant: 460),
            centerXAnchor.constraint(equalTo: window.centerXAnchor)
        ])
        // Total bottom gap = base spacing.m + caller-supplied
        // inset for chrome the window's safeAreaLayoutGuide
        // doesn't account for (tab bar, mini player, etc.).
        let bottom = bottomAnchor.constraint(
            equalTo: window.safeAreaLayoutGuide.bottomAnchor,
            constant: -(Sumi.Spacing.m + bottomInset)
        )
        self.bottomConstraint = bottom
        bottom.isActive = true
        window.layoutIfNeeded()

        // Spring slide-in + progress drain start TOGETHER. The
        // previous version started the drain in the spring's
        // completion handler — adding ~340 ms before the bar
        // first moved. Running them in parallel: the bar begins
        // draining the moment the toast becomes visible.
        //
        // Reduce Motion path: replace the slide+scale+fade
        // composite with a plain crossfade. Same duration,
        // identity transform throughout — no decorative motion.
        // Progress bar still drains (informative timing cue,
        // not decoration), haptic still fires.
        if Sumi.Motion.isReduced {
            transform = .identity
            alpha = 0
            UIView.animate(
                withDuration: Sumi.Motion.standard,
                delay: 0,
                options: [.curveEaseOut, .allowUserInteraction]
            ) {
                self.alpha = 1
            }
        } else {
            // Slide-up + scale-up + fade. Start 24pt below and
            // 0.92× scale; spring overshoot lands the toast at
            // rest with a soft "pop".
            transform = CGAffineTransform(translationX: 0, y: 24)
                .scaledBy(x: 0.92, y: 0.92)
            alpha = 0
            UIView.animate(
                withDuration: Sumi.Motion.standard,
                delay: 0,
                usingSpringWithDamping: 0.78,
                initialSpringVelocity: 0.5,
                options: [.allowUserInteraction]
            ) {
                self.transform = .identity
                self.alpha = 1
            }
        }
        startProgressAnimation()

        fireAppearHaptic()
    }

    private func startProgressAnimation() {
        guard didLayout else { return }
        isProgressAnimating = true
        let targetWidth: CGFloat = 0
        UIView.animate(
            withDuration: item.duration,
            delay: 0,
            options: [.curveLinear, .allowUserInteraction],
            animations: {
                var f = self.progressBar.frame
                f.size.width = targetWidth
                self.progressBar.frame = f
            },
            completion: { [weak self] finished in
                // `finished` is false when the animation was
                // interrupted (e.g. dismissAll cancelled it,
                // or the view was removed). In those paths the
                // coordinator has already taken over — we MUST
                // NOT fire onProgressFinished or we double-
                // dismiss.
                guard finished else { return }
                self?.onProgressFinished?()
            }
        )
    }

    fileprivate func dismiss(animated: Bool, completion: @escaping () -> Void) {
        guard animated else {
            removeFromSuperview()
            completion()
            return
        }
        // Pick the exit motion based on whether the user is
        // mid-swipe or this is a non-gestured dismiss (timer
        // expired, tap on card, programmatic dismissAll).
        //
        // Mid-swipe: the toast is ALREADY translated downward
        // (transform.ty > 0). Exit MUST continue that motion
        // off-screen — otherwise the animation interpolates
        // back from the dragged position and the user sees a
        // visible "twitch backwards" before the toast fades.
        // Reduce Motion does NOT apply here — this is direct
        // manipulation, the user themselves moved the toast.
        //
        // Untouched + Reduce Motion: pure fade, no slide.
        // Untouched + default: gentle 12pt slide + 0.96 scale
        // + fade — the same micro-motion used for auto-dismiss.
        let currentTy = transform.ty
        let isMidSwipe = currentTy > 4
        let targetTransform: CGAffineTransform
        if isMidSwipe {
            targetTransform = CGAffineTransform(translationX: 0, y: max(180, currentTy + 80))
        } else if Sumi.Motion.isReduced {
            targetTransform = .identity
        } else {
            targetTransform = CGAffineTransform(translationX: 0, y: 12).scaledBy(x: 0.96, y: 0.96)
        }

        UIView.animate(
            withDuration: Sumi.Motion.fast,
            delay: 0,
            options: [.curveEaseOut, .allowUserInteraction]
        ) {
            self.transform = targetTransform
            self.alpha = 0
        } completion: { _ in
            self.removeFromSuperview()
            completion()
        }
    }

    // MARK: - Haptics

    private func fireAppearHaptic() {
        switch item.style {
        case .info:
            UISelectionFeedbackGenerator().selectionChanged()
        case .success:
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        case .warning:
            UINotificationFeedbackGenerator().notificationOccurred(.warning)
        case .danger:
            UINotificationFeedbackGenerator().notificationOccurred(.error)
        }
    }

    // MARK: - Interactions

    @objc private func actionTapped() {
        onTapAction?()
    }

    @objc private func cardTapped(_ recognizer: UITapGestureRecognizer) {
        // Only dismiss if tap landed outside the action button —
        // tapping action fires its own handler via UIButton.
        let loc = recognizer.location(in: self)
        if item.action != nil, actionButton.frame.insetBy(dx: -8, dy: -8).contains(loc) {
            return
        }
        onDismiss?()
    }

    @objc private func panned(_ recognizer: UIPanGestureRecognizer) {
        let translation = recognizer.translation(in: self)
        switch recognizer.state {
        case .changed:
            // Allow downward drag freely; rubber-band on up.
            let dy = translation.y >= 0
                ? translation.y
                : -sqrt(-translation.y) * 2
            transform = CGAffineTransform(translationX: 0, y: dy)
        case .ended, .cancelled:
            let velocity = recognizer.velocity(in: self).y
            // Either pulled 30pt+ down or flung fast → dismiss.
            if translation.y > 30 || velocity > 600 {
                onDismiss?()
            } else {
                UIView.animate(
                    withDuration: 0.32,
                    delay: 0,
                    usingSpringWithDamping: 0.82,
                    initialSpringVelocity: 0.4,
                    options: [.allowUserInteraction]
                ) {
                    self.transform = .identity
                }
            }
        default:
            break
        }
    }
}

