import UIKit
import Sumi
import SumiToast

// ToastPlaygroundViewController — design-time playground for
// ToastComponent.
//
// Lets the developer fire each toast variant on a tap, see the
// queuing behaviour by firing several in a row, and toggle
// style / action presence to verify every combination. Doubles
// as a manual smoke test — if a refactor breaks any case, you
// see it here within seconds, no need to reach into the host app's full
// reader flow.

@MainActor
public final class ToastPlaygroundViewController: UIViewController {

    private let scroll = PlaygroundScrollView()
    private let stack = UIStackView()

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

        NSLayoutConstraint.activate([
            scroll.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scroll.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            scroll.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: view.trailingAnchor),

            stack.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor, constant: Sumi.Spacing.l),
            stack.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor, constant: -Sumi.Spacing.xxl),
            stack.leadingAnchor.constraint(equalTo: scroll.contentLayoutGuide.leadingAnchor, constant: Sumi.Spacing.l),
            stack.trailingAnchor.constraint(equalTo: scroll.contentLayoutGuide.trailingAnchor, constant: -Sumi.Spacing.l),
            stack.widthAnchor.constraint(equalTo: scroll.frameLayoutGuide.widthAnchor, constant: -Sumi.Spacing.l * 2)
        ])

        addSection("Styles")
        addButton("Info — short", style: .info) {
            Toast.show("Chapter 12 marked as read")
        }
        addButton("Success — chapter downloaded", style: .success) {
            Toast.show("Chapter 12 downloaded", style: .success)
        }
        addButton("Warning — slow source", style: .warning) {
            Toast.show("Source is responding slowly. Refresh may take a while.", style: .warning)
        }
        addButton("Danger — download failed", style: .danger) {
            Toast.show("Failed to download chapter 12. Tap to retry.", style: .danger)
        }

        addSection("With action")
        addButton("Undo mark-as-read", style: .info) {
            Toast.show(
                "Marked 5 chapters as read",
                style: .info,
                action: .init(title: "Undo") {
                    Toast.show("Reverted 5 chapters", style: .success)
                }
            )
        }
        addButton("Translation failed — retry", style: .danger) {
            Toast.show(
                "Translation failed for chapter 7",
                style: .danger,
                action: .init(title: "Retry") {
                    Toast.show("Retrying translation…", style: .info)
                }
            )
        }

        addSection("Queue")
        addButton("Fire 5 toasts in a row", style: .info) {
            for (i, message) in [
                "Chapter 8 downloaded",
                "Chapter 9 downloaded",
                "Chapter 10 downloaded",
                "Library refreshed",
                "Sync complete"
            ].enumerated() {
                Toast.show(message, style: i == 4 ? .success : .info)
            }
        }
        addButton("Long message", style: .info) {
            Toast.show("This is a much longer toast message demonstrating that the layout wraps to multiple lines and the duration heuristic accounts for reading time.")
        }

        addSection("Maintenance")
        addButton("Dismiss all", style: .danger) {
            Toast.dismissAll()
        }
    }

    private func addSection(_ title: String) {
        let label = UILabel()
        label.text = title.uppercased()
        label.font = Sumi.Font.captionEmphasised()
        label.textColor = Sumi.Color.textSecondary
        stack.addArrangedSubview(label)
        stack.setCustomSpacing(Sumi.Spacing.s, after: label)
    }

    private func addButton(_ title: String, style: Toast.Style, action: @escaping () -> Void) {
        let button = PlaygroundButtonRow(title: title, accent: accentColor(for: style))
        button.onTap = action
        stack.addArrangedSubview(button)
    }

    private func accentColor(for style: Toast.Style) -> UIColor {
        switch style {
        case .info:    return Sumi.Color.accent
        case .success: return Sumi.Color.success
        case .warning: return Sumi.Color.warning
        case .danger:  return Sumi.Color.danger
        }
    }
}
