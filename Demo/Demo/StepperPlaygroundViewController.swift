import UIKit
import Sumi
import SumiDialog
import SumiStepper

// StepperPlaygroundViewController — exercises every variant
// of `SumiStepperView` so the visual + interaction behaviour
// can be poked directly.

@MainActor
public final class StepperPlaygroundViewController: UIViewController {

    private let scroll = PlaygroundScrollView()
    private let stack = UIStackView()
    private let statusLabel = StatusLabel()

    public override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = Sumi.Color.surface

        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.alwaysBounceVertical = true
        view.addSubview(scroll)

        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.axis = .vertical
        stack.spacing = Sumi.Spacing.m
        stack.alignment = .fill
        scroll.addSubview(stack)

        view.addSubview(statusLabel)

        NSLayoutConstraint.activate([
            scroll.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scroll.bottomAnchor.constraint(equalTo: statusLabel.topAnchor, constant: -Sumi.Spacing.m),
            scroll.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: view.trailingAnchor),

            statusLabel.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: Sumi.Spacing.l),
            statusLabel.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -Sumi.Spacing.l),
            statusLabel.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -Sumi.Spacing.m),

            stack.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor, constant: Sumi.Spacing.l),
            stack.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor, constant: -Sumi.Spacing.xxl),
            stack.leadingAnchor.constraint(equalTo: scroll.contentLayoutGuide.leadingAnchor, constant: Sumi.Spacing.l),
            stack.trailingAnchor.constraint(equalTo: scroll.contentLayoutGuide.trailingAnchor, constant: -Sumi.Spacing.l),
            stack.widthAnchor.constraint(equalTo: scroll.frameLayoutGuide.widthAnchor, constant: -Sumi.Spacing.l * 2)
        ])

        let hint = UILabel()
        hint.text = "Hero-sized integer stepper card — 72pt-bold value, 64pt circular ± buttons, press-and-hold auto-repeat with tapering interval, selection haptic on every tick. Designed for SumiDialog `customContent` where the adjusted value is the entire interaction surface (chapter count, page limit, day count)."
        hint.font = Sumi.Font.caption()
        hint.textColor = Sumi.Color.textSecondary
        hint.numberOfLines = 0
        stack.addArrangedSubview(hint)
        stack.setCustomSpacing(Sumi.Spacing.xl, after: hint)

        addSection("Embedded in dialog (no buttons — dismiss commits)")
        addStepperButton("Chapters read — with progress hairline") {
            let stepper = SumiStepperView(
                initial: 12,
                range: 0...160,
                caption: "of 120",
                progressTotal: 120
            )
            _ = await SumiDialog.present(
                title: "Chapters read",
                message: "AniList",
                customContent: stepper,
                actions: []
            )
            return stepper.currentValue
        }

        addStepperButton("Unbounded — no total, no progress fill") {
            let stepper = SumiStepperView(
                initial: 0,
                range: 0...9999,
                caption: "of ?",
                progressTotal: nil
            )
            _ = await SumiDialog.present(
                title: "Pages read",
                message: "Ongoing series",
                customContent: stepper,
                actions: []
            )
            return stepper.currentValue
        }

        addStepperButton("Tight range — 1…7 days") {
            let stepper = SumiStepperView(
                initial: 1,
                range: 1...7,
                caption: "day(s)",
                progressTotal: 7
            )
            _ = await SumiDialog.present(
                title: "Refresh every",
                message: "Smart Update interval",
                customContent: stepper,
                actions: []
            )
            return stepper.currentValue
        }

        addStepperButton("At upper bound — minus only") {
            let stepper = SumiStepperView(
                initial: 100,
                range: 0...100,
                caption: "of 100",
                progressTotal: 100
            )
            _ = await SumiDialog.present(
                title: "At max",
                message: "Plus button visually disabled at boundary",
                customContent: stepper,
                actions: []
            )
            return stepper.currentValue
        }

        addSection("With Cancel / Save buttons (compare)")
        addStepperButton("Same stepper + standard action row") {
            let stepper = SumiStepperView(
                initial: 24,
                range: 0...100,
                caption: "of 100",
                progressTotal: 100
            )
            let picked = await SumiDialog.present(
                title: "Chapters read",
                message: "With explicit Cancel / Save",
                customContent: stepper,
                actions: [
                    .init(title: "Cancel", style: .cancel),
                    .init(title: "Save", style: .primary)
                ]
            )
            return picked?.style == .primary ? stepper.currentValue : nil
        }
    }

    // MARK: - Builder helpers

    private func addSection(_ title: String) {
        let label = UILabel()
        label.text = title.uppercased()
        label.font = Sumi.Font.captionEmphasised()
        label.textColor = Sumi.Color.textSecondary
        stack.addArrangedSubview(label)
        stack.setCustomSpacing(Sumi.Spacing.s, after: label)
    }

    /// Variant of `addButton` that surfaces the final stepper
    /// value picked by the user. nil → "dismissed".
    private func addStepperButton(
        _ title: String,
        action: @escaping () async -> Int?
    ) {
        let button = PlaygroundButtonRow(title: title, accent: Sumi.Color.accent)
        button.onTap = { [weak self] in
            Task { @MainActor in
                let value = await action()
                if let value {
                    self?.statusLabel.status = "saved: \(value)"
                } else {
                    self?.statusLabel.status = "dismissed"
                }
            }
        }
        stack.addArrangedSubview(button)
    }
}
