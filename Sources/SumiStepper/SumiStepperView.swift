import UIKit
import Sumi

// SumiStepperView — large, hero-sized integer stepper card.
//
// Use cases: chapter count, page limit, day count, anything
// where the user adjusts ONE integer and the value itself is
// the focus of the screen. NOT for compact form-field steppers
// — those fit inline UIStepper better.
//
// Visual:
//
//   ┌──────────────────────────────┐
//   │           47                 │  ← 72pt bold, hero size
//   │         of 120               │  ← optional caption
//   │ ─────────████──────────────  │  ← optional progress hairline
//   │     ( - )           ( + )    │  ← 64pt circular buttons
//   └──────────────────────────────┘
//
// Behaviour:
//   • Single tap on ± → step ±1, selection haptic
//   • Press-and-hold → auto-repeat with tapering interval
//     (0.28s → 0.06s over ~25 ticks)
//   • Range-clamped: ± at the boundary becomes a no-op
//     (button visually disables, no haptic on lockout)
//   • Progress hairline only when `progressTotal != nil`
//     and `progressTotal > 0` — quiet completion cue
//   • `onChange` callback fires on every tick so callers can
//     mirror state without polling
//
// Designed for embedding as `customContent` in `SumiDialog`.
// The dialog provides title / message / dismiss; this view
// provides interaction. Callers read `currentValue` after
// dismiss.

@MainActor
public final class SumiStepperView: UIView {

    public init(
        initial: Int,
        range: ClosedRange<Int>,
        caption: String? = nil,
        progressTotal: Int? = nil,
        accentColor: UIColor = Sumi.Color.accent
    ) {
        precondition(range.contains(initial), "initial must be within range")
        self.range = range
        self.progressTotal = progressTotal
        self.accentColor = accentColor
        self.currentValue = initial
        super.init(frame: .zero)
        buildLayout(caption: caption)
        refreshUI()
    }

    @available(*, unavailable)
    public required init?(coder: NSCoder) { fatalError("init(coder:) not supported") }

    // MARK: - Public surface

    /// Current stepper value. Read after dialog dismiss to
    /// commit to the backing model.
    public private(set) var currentValue: Int

    /// Fires on every accepted tick (after clamp). NOT fired
    /// when a tap is rejected at the boundary — saves callers
    /// from filtering no-ops in their handler.
    public var onChange: ((Int) -> Void)?

    // MARK: - Private state

    private let range: ClosedRange<Int>
    private let progressTotal: Int?
    private let accentColor: UIColor
    private let haptic = UISelectionFeedbackGenerator()

    private let valueLabel = UILabel()
    private let captionLabel = UILabel()
    private let minusButton = RoundStepperButton(symbol: "minus")
    private let plusButton = RoundStepperButton(symbol: "plus")
    private let progressTrack = UIView()
    private let progressFill = UIView()
    private var progressFillWidthConstraint: NSLayoutConstraint!

    private var repeatTimer: Timer?
    private var repeatTickCount = 0
    private var repeatDirection: Int = 0

    // MARK: - Layout

    private func buildLayout(caption: String?) {
        translatesAutoresizingMaskIntoConstraints = false
        haptic.prepare()

        valueLabel.font = .systemFont(ofSize: 72, weight: .bold)
        valueLabel.textAlignment = .center
        valueLabel.textColor = Sumi.Color.textPrimary
        valueLabel.adjustsFontSizeToFitWidth = true
        valueLabel.minimumScaleFactor = 0.5

        captionLabel.font = Sumi.Font.caption()
        captionLabel.textAlignment = .center
        captionLabel.textColor = Sumi.Color.textSecondary
        captionLabel.text = caption
        captionLabel.isHidden = (caption == nil)

        progressTrack.translatesAutoresizingMaskIntoConstraints = false
        progressTrack.backgroundColor = Sumi.Color.textPrimary.withAlphaComponent(0.08)
        progressTrack.layer.cornerRadius = 1.5
        progressTrack.clipsToBounds = true
        progressTrack.isHidden = (progressTotal == nil || (progressTotal ?? 0) <= 0)
        addSubview(progressTrack)

        progressFill.translatesAutoresizingMaskIntoConstraints = false
        progressFill.backgroundColor = accentColor
        progressFill.layer.cornerRadius = 1.5
        progressTrack.addSubview(progressFill)

        minusButton.onTap = { [weak self] in self?.step(by: -1) }
        plusButton.onTap = { [weak self] in self?.step(by: +1) }
        minusButton.onHoldBegan = { [weak self] in self?.beginRepeat(direction: -1) }
        plusButton.onHoldBegan = { [weak self] in self?.beginRepeat(direction: +1) }
        minusButton.onHoldEnded = { [weak self] in self?.endRepeat() }
        plusButton.onHoldEnded = { [weak self] in self?.endRepeat() }

        let textStack = UIStackView(arrangedSubviews: [valueLabel, captionLabel])
        textStack.axis = .vertical
        textStack.alignment = .center
        textStack.spacing = 2
        textStack.translatesAutoresizingMaskIntoConstraints = false

        let buttonsRow = UIStackView(arrangedSubviews: [minusButton, plusButton])
        buttonsRow.axis = .horizontal
        buttonsRow.alignment = .center
        buttonsRow.distribution = .equalSpacing
        buttonsRow.spacing = 64
        buttonsRow.translatesAutoresizingMaskIntoConstraints = false

        addSubview(textStack)
        addSubview(buttonsRow)

        // 0-width starter constraint; `refreshUI` swaps it for
        // a multiplier-bound constraint reflecting actual progress.
        progressFillWidthConstraint =
            progressFill.widthAnchor.constraint(equalTo: progressTrack.widthAnchor, multiplier: 0)

        NSLayoutConstraint.activate([
            textStack.topAnchor.constraint(equalTo: topAnchor, constant: 4),
            textStack.centerXAnchor.constraint(equalTo: centerXAnchor),
            textStack.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor),
            textStack.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor),

            progressTrack.topAnchor.constraint(equalTo: textStack.bottomAnchor, constant: 14),
            progressTrack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            progressTrack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            progressTrack.heightAnchor.constraint(equalToConstant: 3),

            progressFill.topAnchor.constraint(equalTo: progressTrack.topAnchor),
            progressFill.bottomAnchor.constraint(equalTo: progressTrack.bottomAnchor),
            progressFill.leadingAnchor.constraint(equalTo: progressTrack.leadingAnchor),
            progressFillWidthConstraint,

            buttonsRow.topAnchor.constraint(equalTo: progressTrack.bottomAnchor, constant: 22),
            buttonsRow.centerXAnchor.constraint(equalTo: centerXAnchor),
            buttonsRow.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -4)
        ])
    }

    // MARK: - Stepping

    private func step(by delta: Int) {
        let proposed = currentValue + delta
        guard range.contains(proposed) else {
            endRepeat()
            return
        }
        currentValue = proposed
        haptic.selectionChanged()
        haptic.prepare()
        refreshUI()
        onChange?(currentValue)
    }

    private func refreshUI() {
        valueLabel.text = "\(currentValue)"
        let multiplier: CGFloat = {
            guard let total = progressTotal, total > 0 else { return 0 }
            let fraction = min(CGFloat(currentValue) / CGFloat(total), 1.0)
            return fraction
        }()
        // UIKit doesn't let you mutate a constraint's multiplier
        // — recreate it. Activation order matters: deactivate
        // the old one first, build the new one, then activate.
        NSLayoutConstraint.deactivate([progressFillWidthConstraint])
        progressFillWidthConstraint =
            progressFill.widthAnchor.constraint(equalTo: progressTrack.widthAnchor, multiplier: multiplier)
        progressFillWidthConstraint.isActive = true
        UIView.animate(
            withDuration: 0.18,
            delay: 0,
            options: [.curveEaseOut, .beginFromCurrentState],
            animations: { self.layoutIfNeeded() }
        )

        minusButton.isEnabled = currentValue > range.lowerBound
        plusButton.isEnabled = currentValue < range.upperBound
    }

    // MARK: - Auto-repeat on hold

    private func beginRepeat(direction: Int) {
        endRepeat()
        repeatDirection = direction
        repeatTickCount = 0
        scheduleNextTick(after: 0.28)
    }

    private func scheduleNextTick(after interval: TimeInterval) {
        repeatTimer = Timer.scheduledTimer(
            withTimeInterval: interval,
            repeats: false
        ) { [weak self] _ in
            // Timer fires on the run loop where it was
            // scheduled (main here), but its closure isn't
            // @MainActor — hop explicitly. Matches the
            // pattern SumiAlert's hold-to-confirm uses.
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.step(by: self.repeatDirection)
                self.repeatTickCount += 1
                // Tapering interval: 0.28 → 0.06 over ~25
                // ticks. Picked so 1s hold ≈ 5 ticks
                // (responsive), 3s hold ≈ 50 ticks (catch-up
                // territory), and an accidental long-press
                // isn't runaway.
                let next = max(0.06, 0.28 - Double(self.repeatTickCount) * 0.01)
                self.scheduleNextTick(after: next)
            }
        }
    }

    private func endRepeat() {
        repeatTimer?.invalidate()
        repeatTimer = nil
        repeatDirection = 0
        repeatTickCount = 0
    }
}
