import UIKit
import Sumi

// AlertChrome — shared internal visuals for every presentation
// class in the SumiAlert module.
//
// What lives here:
//   • `AlertButton`        — single tappable action label (NOT
//                            a UIControl; touch tracking lives
//                            on the parent for finger-drag).
//   • `AlertButtonsView`   — manual-frame button row with
//                            native-style finger-drag selection.
//   • `makeAlertIconView`  — builds the optional 44pt SF Symbol
//                            shown above title + message.
//
// All are `internal` (no access modifier) so they're shared
// across the presentation files within this module but stay
// invisible to consumers.

// MARK: - AlertButton
//
// AlertButton — visual + action holder, NOT a UIControl.
//
// UIControl captures touches: once you press down on Button A,
// any subsequent move/end events go to Button A even if your
// finger drifts over Button B. That kills the native iOS
// "drag your finger across the alert and release on the chosen
// option" UX. So buttons are plain views; touch tracking lives
// on the parent `AlertButtonsView` which hit-tests on every
// move and forwards the pick to whichever button is under the
// finger at release time.

@MainActor
final class AlertButton: UIView {
    let action: Alert.Action
    var onTap: (() -> Void)?
    private let label = UILabel()
    private let spinner = UIActivityIndicatorView(style: .medium)
    private let tintColor_: UIColor

    init(action: Alert.Action, emphasised: Bool) {
        self.action = action
        let color: UIColor
        switch action.style {
        case .default:     color = Sumi.Color.accent
        case .primary:     color = Sumi.Color.accent
        case .destructive: color = Sumi.Color.danger
        case .cancel:      color = Sumi.Color.textSecondary
        }
        self.tintColor_ = color
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false

        let font: UIFont = (emphasised || action.style == .primary || action.style == .destructive)
            ? Sumi.Font.bodyEmphasised()
            : Sumi.Font.body()

        label.translatesAutoresizingMaskIntoConstraints = false
        label.text = action.title
        label.textColor = color
        label.font = font
        label.textAlignment = .center
        addSubview(label)

        // Spinner for async loading state. Hidden by default;
        // shown by `setLoading(true)` when the action's
        // `asyncHandler` is running. Tinted to match the label
        // colour so the loading state reads as the same button
        // doing work, not a generic spinner.
        spinner.translatesAutoresizingMaskIntoConstraints = false
        spinner.hidesWhenStopped = true
        spinner.color = color
        addSubview(spinner)

        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: centerXAnchor),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
            spinner.centerXAnchor.constraint(equalTo: centerXAnchor),
            spinner.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) not supported") }

    /// Sensible intrinsic size derived from the label plus
    /// breathing room. In production `AlertButtonsView` always
    /// assigns frames directly so this value is ignored — it
    /// exists so the button survives being dropped into a
    /// `UIStackView` / generic AutoLayout context and still
    /// renders at a tappable size. The 44pt floor is Apple's
    /// minimum-tap-target guideline; 32pt horizontal gives the
    /// text room from the edge.
    override var intrinsicContentSize: CGSize {
        let labelSize = label.intrinsicContentSize
        return CGSize(
            width: labelSize.width + 32,
            height: max(labelSize.height + 12, 44)
        )
    }

    /// Called by `AlertButtonsView` while the user drags their
    /// finger over this button. Sets the highlight overlay
    /// without animation on rapid changes (animation would
    /// queue up and lag the visual behind the finger).
    func setHighlighted(_ highlighted: Bool, animated: Bool) {
        let target: UIColor = highlighted
            ? Sumi.Color.pressOverlay
            : .clear
        if animated {
            UIView.animate(withDuration: 0.12) { self.backgroundColor = target }
        } else {
            backgroundColor = target
        }
    }

    /// Crossfade between label and spinner on async loading
    /// transitions. Both alphas animate in parallel — the
    /// spinner doesn't linger at full visibility while the
    /// label fades back in (and vice-versa).
    func setLoading(_ loading: Bool, animated: Bool = true) {
        let labelTarget: CGFloat = loading ? 0 : 1
        let spinnerTarget: CGFloat = loading ? 1 : 0
        if loading {
            // Start invisible so we can fade IN alongside the
            // label fading OUT — otherwise the spinner pops
            // at full opacity before the label has dimmed.
            spinner.alpha = 0
            spinner.startAnimating()
        }
        let block = {
            self.label.alpha = labelTarget
            self.spinner.alpha = spinnerTarget
        }
        if animated && !Sumi.Motion.isReduced {
            UIView.animate(withDuration: 0.18, animations: block) { _ in
                if !loading {
                    self.spinner.stopAnimating()
                    // Reset alpha so the next loading cycle
                    // doesn't inherit alpha 0 (which would
                    // skip the fade-in).
                    self.spinner.alpha = 1
                }
            }
        } else {
            block()
            if !loading {
                spinner.stopAnimating()
                spinner.alpha = 1
            }
        }
    }

    /// Used by `AlertButtonsView` to dim the non-loading
    /// buttons while another button's async handler is running.
    func setDimmed(_ dimmed: Bool, animated: Bool) {
        let target: CGFloat = dimmed ? 0.35 : 1
        let block = { self.alpha = target }
        if animated && !Sumi.Motion.isReduced {
            UIView.animate(withDuration: 0.15, animations: block)
        } else {
            block()
        }
    }
}

// MARK: - AlertButtonsView (manual frame layout + finger-drag)
//
// Lays out the action button row using raw frames (not a
// UIStackView) so 1pt separators between buttons render
// crisply at any resolution. UIStackView with `.fillEqually`
// stretches a 1-pixel separator to 1/N of the row width,
// producing a visible gray band between buttons — manual
// layout sidesteps it.
//
// Layout rules:
//   • Top hairline separator across the whole card width.
//   • Horizontal: actionWidth = floor(width / count) for all
//     buttons except the last, which takes the remainder so
//     the right edge lines up exactly with the card border —
//     no fractional gap from `floor()`.
//   • Vertical: actionHeight = floor(totalHeight / count),
//     last button takes the remainder.
//   • Inter-button separator is a 1-screen-pixel-wide hairline
//     at the boundary between buttons.
//
// Finger-drag selection (matches native `UIAlertController`):
//   • `touchesBegan/Moved` hit-test the touch point against the
//     button frames and update which button is highlighted.
//   • A `UISelectionFeedbackGenerator.selectionChanged()` ticks
//     on every highlight change for the same tactile micro-
//     click iOS native alerts have.
//   • `touchesEnded` fires the picked action's `onTap` if the
//     finger is on a button at release time; finger released
//     outside the buttons row = no action.
//   • `touchesCancelled` clears highlight; system swallowed the
//     touch (multi-touch, system gesture), the user has to tap
//     again. No "did the user mean to pick?" ambiguity.

@MainActor
final class AlertButtonsView: UIView {

    enum Layout { case horizontal, vertical }

    private let buttons: [AlertButton]
    private let interSeparators: [UIView]
    private let topSeparator = UIView()
    private let layout: Layout
    private static let buttonHeight: CGFloat = 50

    private weak var highlightedButton: AlertButton?
    private weak var loadingButton: AlertButton?
    private let selectionHaptic = UISelectionFeedbackGenerator()
    private let onPick: (Alert.Action) -> Void

    /// True when an async action handler is running. Touch
    /// tracking is gated while this is set so the user can't
    /// pick a different action mid-async.
    var isLoading: Bool { loadingButton != nil }

    init(
        actions: [Alert.Action],
        emphasisedIndex: Int?,
        layout: Layout,
        onPick: @escaping (Alert.Action) -> Void
    ) {
        self.layout = layout
        self.onPick = onPick
        var buttons: [AlertButton] = []
        var separators: [UIView] = []
        for (i, action) in actions.enumerated() {
            let btn = AlertButton(action: action, emphasised: i == emphasisedIndex)
            // Per-button onTap callback is unused — picks flow
            // through `onPick(action:)` from `touchesEnded` so
            // the parent owns the tap → action mapping.
            buttons.append(btn)
            if i > 0 {
                let sep = UIView()
                sep.backgroundColor = Sumi.Color.separator
                separators.append(sep)
            }
        }
        self.buttons = buttons
        self.interSeparators = separators
        super.init(frame: .zero)
        topSeparator.backgroundColor = Sumi.Color.separator
        addSubview(topSeparator)
        // Children are positioned by manual frame (see
        // `layoutSubviews`). `AlertButton.init` sets
        // `translatesAutoresizingMaskIntoConstraints = false` so
        // its internal label can use auto-layout — but as a
        // child here we need frame-driven sizing, so flip it
        // back on after construction. Separators are plain
        // UIView and already have `true` by default.
        for btn in buttons {
            btn.translatesAutoresizingMaskIntoConstraints = true
            addSubview(btn)
        }
        for sep in separators { addSubview(sep) }
        selectionHaptic.prepare()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) not supported") }

    override var intrinsicContentSize: CGSize {
        let pixel = 1.0 / UIScreen.main.scale
        switch layout {
        case .horizontal:
            return CGSize(width: UIView.noIntrinsicMetric, height: Self.buttonHeight + pixel)
        case .vertical:
            return CGSize(width: UIView.noIntrinsicMetric,
                          height: Self.buttonHeight * CGFloat(buttons.count) + pixel)
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let pixel = 1.0 / UIScreen.main.scale
        topSeparator.frame = CGRect(x: 0, y: 0, width: bounds.width, height: pixel)
        let rowOriginY: CGFloat = pixel
        let rowHeight: CGFloat = bounds.height - pixel

        switch layout {
        case .horizontal:
            let count = buttons.count
            let nominalWidth = floor(bounds.width / CGFloat(count))
            var x: CGFloat = 0
            for (i, btn) in buttons.enumerated() {
                let w: CGFloat = (i == count - 1) ? (bounds.width - x) : nominalWidth
                btn.frame = CGRect(x: x, y: rowOriginY, width: w, height: rowHeight)
                if i > 0 {
                    interSeparators[i - 1].frame = CGRect(
                        x: x - pixel, y: rowOriginY,
                        width: pixel, height: rowHeight
                    )
                }
                x += w
            }
        case .vertical:
            let count = buttons.count
            let nominalHeight = floor(rowHeight / CGFloat(count))
            var y: CGFloat = rowOriginY
            for (i, btn) in buttons.enumerated() {
                let h: CGFloat = (i == count - 1) ? (rowOriginY + rowHeight - y) : nominalHeight
                btn.frame = CGRect(x: 0, y: y, width: bounds.width, height: h)
                if i > 0 {
                    interSeparators[i - 1].frame = CGRect(
                        x: 0, y: y - pixel,
                        width: bounds.width, height: pixel
                    )
                }
                y += h
            }
        }
    }

    // MARK: - Async loading state

    /// Enter loading mode for `action`: that button shows a
    /// spinner, all OTHER buttons dim and stop responding to
    /// touch. Touch on the loading button itself is also
    /// suppressed — the user can't double-trigger.
    func startLoading(for action: Alert.Action) {
        guard let target = buttons.first(where: { $0.action.title == action.title && $0.action.style == action.style }) else { return }
        loadingButton = target
        target.setLoading(true, animated: true)
        for btn in buttons where btn !== target {
            btn.setDimmed(true, animated: true)
        }
        // Cancel any in-progress highlight.
        highlightedButton?.setHighlighted(false, animated: true)
        highlightedButton = nil
    }

    /// Exit loading mode — restore normal state for all
    /// buttons. Called by the presentation after the async
    /// handler throws (so the user can pick again).
    func stopLoading() {
        guard let target = loadingButton else { return }
        target.setLoading(false, animated: true)
        for btn in buttons where btn !== target {
            btn.setDimmed(false, animated: true)
        }
        loadingButton = nil
    }

    // MARK: - Finger-drag selection

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesBegan(touches, with: event)
        // Gate touch input while an async action is in flight —
        // user can't pick a different button mid-await.
        guard !isLoading else { return }
        guard let touch = touches.first else { return }
        updateHighlight(at: touch.location(in: self))
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesMoved(touches, with: event)
        guard !isLoading else { return }
        guard let touch = touches.first else { return }
        updateHighlight(at: touch.location(in: self))
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesEnded(touches, with: event)
        guard !isLoading else { return }
        // Pick whichever button the finger is on at release. If
        // the finger left the row entirely (highlightedButton ==
        // nil), no action fires — the alert stays open. Matches
        // native UIAlertController.
        if let picked = highlightedButton {
            picked.setHighlighted(false, animated: true)
            onPick(picked.action)
        }
        highlightedButton = nil
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesCancelled(touches, with: event)
        highlightedButton?.setHighlighted(false, animated: true)
        highlightedButton = nil
    }

    private func updateHighlight(at point: CGPoint) {
        // Hit-test by frame containment rather than `hitTest(_:)`
        // — separators are inert subviews and we want the
        // touch to count for the adjacent button even if the
        // finger is exactly on a hairline pixel.
        let hit = buttons.first { $0.frame.contains(point) }
        guard hit !== highlightedButton else { return }
        highlightedButton?.setHighlighted(false, animated: false)
        hit?.setHighlighted(true, animated: false)
        highlightedButton = hit
        if hit != nil {
            // Tactile click on every transition between buttons,
            // including the initial press-down. Skipped when
            // finger leaves the row (hit == nil) so users don't
            // get a click for "you released nothing".
            selectionHaptic.selectionChanged()
            selectionHaptic.prepare()
        }
    }
}

// MARK: - Icon view helper
//
// Builds the iconography that sits above title + message when
// callers pass `icon:` to `Alert.present` / `Alert.presentText`.
// Wrapped in a fixed-height container so the SF Symbol stays
// at its configured 44pt point size (without the wrapper, the
// stack view's `alignment: .fill` stretches an `UIImageView`
// vertically and the symbol scales up with it).

@MainActor
func makeAlertIconView(icon: UIImage, tint: UIColor?) -> UIView {
    let imageView = UIImageView(image: icon)
    imageView.translatesAutoresizingMaskIntoConstraints = false
    imageView.contentMode = .scaleAspectFit
    imageView.tintColor = tint ?? Sumi.Color.accent
    imageView.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 44, weight: .semibold)

    let wrapper = UIView()
    wrapper.translatesAutoresizingMaskIntoConstraints = false
    wrapper.addSubview(imageView)
    NSLayoutConstraint.activate([
        wrapper.heightAnchor.constraint(equalToConstant: 52),
        imageView.centerXAnchor.constraint(equalTo: wrapper.centerXAnchor),
        imageView.centerYAnchor.constraint(equalTo: wrapper.centerYAnchor),
        imageView.widthAnchor.constraint(lessThanOrEqualTo: wrapper.widthAnchor),
        imageView.heightAnchor.constraint(lessThanOrEqualTo: wrapper.heightAnchor)
    ])
    return wrapper
}

// MARK: - AlertIndicatorBox
//
// Rounded-square checkbox indicator matching `SumiPicker`'s
// `IndicatorBox`. Used by `ToggleAlertPresentation`'s rows so
// our checkbox visual language stays consistent across the
// design system — a Picker checkbox and an Alert checkbox
// should be the same shape, colour, and animation.
//
// Duplicated rather than depended-on: SumiAlert importing
// SumiPicker would invert the natural dependency direction
// (alerts are lower-level than pickers). The IndicatorBox is
// small and stable enough that a parallel copy here is the
// right trade-off.

@MainActor
final class AlertIndicatorBox: UIView {

    enum State { case off, on }

    private(set) var state: State = .off
    private let symbolView = UIImageView()

    init() {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        widthAnchor.constraint(equalToConstant: 22).isActive = true
        heightAnchor.constraint(equalToConstant: 22).isActive = true

        layer.cornerRadius = 6
        layer.cornerCurve = .continuous
        layer.borderWidth = 1.5
        layer.borderColor = Sumi.Color.textSecondary.cgColor
        backgroundColor = .clear

        symbolView.translatesAutoresizingMaskIntoConstraints = false
        symbolView.tintColor = .white
        symbolView.contentMode = .center
        addSubview(symbolView)
        NSLayoutConstraint.activate([
            symbolView.centerXAnchor.constraint(equalTo: centerXAnchor),
            symbolView.centerYAnchor.constraint(equalTo: centerYAnchor),
            symbolView.widthAnchor.constraint(equalToConstant: 16),
            symbolView.heightAnchor.constraint(equalToConstant: 16)
        ])
        applyState(animated: false)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) not supported") }

    func setState(_ newState: State, animated: Bool) {
        guard newState != state else { return }
        state = newState
        applyState(animated: animated)
    }

    private func applyState(animated: Bool) {
        let bg: UIColor
        let border: UIColor
        let symbolName: String?
        switch state {
        case .off:
            bg = .clear
            border = Sumi.Color.textSecondary
            symbolName = nil
        case .on:
            bg = Sumi.Color.accent
            border = Sumi.Color.accent
            symbolName = "checkmark"
        }

        let symbolImage = symbolName.flatMap {
            UIImage(systemName: $0, withConfiguration: UIImage.SymbolConfiguration(pointSize: 13, weight: .bold))
        }

        if animated && !Sumi.Motion.isReduced {
            UIView.animate(withDuration: 0.18) {
                self.backgroundColor = bg
                self.layer.borderColor = border.cgColor
            }
            if symbolImage != nil {
                symbolView.image = symbolImage
                symbolView.alpha = 0
                symbolView.transform = CGAffineTransform(scaleX: 0.4, y: 0.4)
                UIView.animate(
                    withDuration: 0.22,
                    delay: 0.04,
                    usingSpringWithDamping: 0.65,
                    initialSpringVelocity: 0.6
                ) {
                    self.symbolView.alpha = 1
                    self.symbolView.transform = .identity
                }
            } else {
                UIView.animate(
                    withDuration: 0.14,
                    animations: {
                        self.symbolView.alpha = 0
                        self.symbolView.transform = CGAffineTransform(scaleX: 0.5, y: 0.5)
                    },
                    completion: { _ in
                        self.symbolView.image = nil
                        self.symbolView.transform = .identity
                    }
                )
            }
        } else {
            backgroundColor = bg
            layer.borderColor = border.cgColor
            symbolView.image = symbolImage
            symbolView.alpha = (symbolImage != nil) ? 1 : 0
            symbolView.transform = .identity
        }
    }
}

// MARK: - HoldToConfirmButton
//
// Used by `HoldAlertPresentation` for nuclear-action alerts.
//
// Behaviour:
//   • Touch-down starts a fill animation that paints the
//     button background with the action's style color over
//     `duration` seconds.
//   • Release before full → cancels: fill drains back to 0,
//     no confirmation.
//   • Release at or past full → fires `onConfirmed`.
//   • Increasing-strength haptic ticks at 25 / 50 / 75 / 100%
//     so the user feels they're "closer".
//
// Internally the fill is a CALayer with its width animated via
// CABasicAnimation (better than UIView.animate for the
// release-cancel case: we read the presentation layer's frame
// and use it as the new "from" when reversing).

@MainActor
final class HoldToConfirmButton: UIView {

    var onConfirmed: (() -> Void)?

    private let title: String
    private let duration: TimeInterval
    private let fillColor: UIColor
    private let label = UILabel()
    private let fillLayer = CALayer()
    private var fillStartedAt: CFTimeInterval = 0
    private var holdTimer: Timer?
    private var hapticsHit: Set<Int> = []  // pct thresholds already fired
    private let selectionHaptic = UISelectionFeedbackGenerator()
    private let successHaptic = UINotificationFeedbackGenerator()

    init(title: String, duration: TimeInterval, fillColor: UIColor) {
        self.title = title
        self.duration = duration
        self.fillColor = fillColor
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        backgroundColor = Sumi.Color.surfaceSubtle
        layer.cornerRadius = 12
        layer.cornerCurve = .continuous
        clipsToBounds = true

        // Fill layer painted with the action color, inserted
        // BELOW the label so the label remains crisp.
        fillLayer.backgroundColor = fillColor.cgColor
        fillLayer.frame = .zero
        layer.addSublayer(fillLayer)

        label.translatesAutoresizingMaskIntoConstraints = false
        label.text = "Hold to \(title.lowercased())"
        label.font = Sumi.Font.bodyEmphasised()
        label.textColor = fillColor
        label.textAlignment = .center
        addSubview(label)
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: centerXAnchor),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
            heightAnchor.constraint(equalToConstant: 54)
        ])
        selectionHaptic.prepare()
        successHaptic.prepare()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) not supported") }

    override func layoutSubviews() {
        super.layoutSubviews()
        // Fill resets to current width on relayout — guard so
        // mid-hold layout passes don't clobber the animation.
        if holdTimer == nil {
            fillLayer.frame = CGRect(x: 0, y: 0, width: 0, height: bounds.height)
        }
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesBegan(touches, with: event)
        startFilling()
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesEnded(touches, with: event)
        // If timer already fired the confirm, ignore touch-end
        // (release after confirmation is fine; we just don't
        // want to "cancel" what already succeeded).
        if holdTimer != nil {
            cancelFilling()
        }
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesCancelled(touches, with: event)
        cancelFilling()
    }

    private func startFilling() {
        hapticsHit.removeAll()
        fillStartedAt = CACurrentMediaTime()
        // Linear fill from 0 to full bounds.width over duration.
        // Reduce Motion: still animate (this is informative —
        // it communicates "how much longer to hold").
        let targetFrame = CGRect(x: 0, y: 0, width: bounds.width, height: bounds.height)
        let anim = CABasicAnimation(keyPath: "frame")
        anim.fromValue = NSValue(cgRect: fillLayer.frame)
        anim.toValue = NSValue(cgRect: targetFrame)
        anim.duration = duration
        anim.timingFunction = CAMediaTimingFunction(name: .linear)
        anim.fillMode = .forwards
        anim.isRemovedOnCompletion = false
        fillLayer.frame = targetFrame
        fillLayer.add(anim, forKey: "fill")

        // Polling timer for haptic milestones + confirmation
        // check. CADisplayLink would be smoother but Timer is
        // enough for 4 haptic events spread across ~1.5 s.
        holdTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            // Timer callback isn't @MainActor; hop manually.
            Task { @MainActor [weak self] in self?.tick() }
        }
        if let timer = holdTimer {
            RunLoop.main.add(timer, forMode: .common)
        }
        label.textColor = Sumi.Color.onAccent
    }

    private func tick() {
        let elapsed = CACurrentMediaTime() - fillStartedAt
        let progress = min(1.0, elapsed / duration)
        let pct = Int(progress * 100)
        for milestone in [25, 50, 75] where pct >= milestone && !hapticsHit.contains(milestone) {
            hapticsHit.insert(milestone)
            selectionHaptic.selectionChanged()
            selectionHaptic.prepare()
        }
        if progress >= 1.0 {
            confirmFire()
        }
    }

    private func confirmFire() {
        holdTimer?.invalidate()
        holdTimer = nil
        successHaptic.notificationOccurred(.success)
        onConfirmed?()
    }

    private func cancelFilling() {
        holdTimer?.invalidate()
        holdTimer = nil
        label.textColor = fillColor
        // Drain the fill back to 0 over a quick reverse.
        // Use presentationLayer's current frame as the "from"
        // so we don't snap to 100% before draining.
        let from = fillLayer.presentation()?.frame ?? fillLayer.frame
        let to = CGRect(x: 0, y: 0, width: 0, height: bounds.height)
        let anim = CABasicAnimation(keyPath: "frame")
        anim.fromValue = NSValue(cgRect: from)
        anim.toValue = NSValue(cgRect: to)
        anim.duration = 0.22
        anim.timingFunction = CAMediaTimingFunction(name: .easeOut)
        anim.fillMode = .forwards
        anim.isRemovedOnCompletion = false
        fillLayer.frame = to
        fillLayer.add(anim, forKey: "fill")
    }
}

