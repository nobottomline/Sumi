import UIKit
import Sumi
import SumiAlert
import SumiTable

// AlertPlaygroundViewController — exercise every Alert variant.
//
// Action feedback is rendered into an inline StatusLabel
// pinned to the bottom of the playground (not Toast — that
// would mix the Toast component into Alert's playground and
// make isolated testing confusing).

@MainActor
public final class AlertPlaygroundViewController: UIViewController {

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

        addSection("One action")
        addButton("OK only (info)") {
            let picked = await Alert.present(
                title: "Update available",
                message: "Version 0.2.0 adds inline translation, dark-mode polish, and faster syncing.",
                actions: [.init(title: "Got it", style: .primary)]
            )
            return picked
        }

        addSection("Two actions — horizontal layout")
        addButton("Cancel / Confirm") {
            await Alert.present(
                title: "Add to library?",
                message: "This manga will be added to your library and updates checked daily.",
                actions: [
                    .init(title: "Not now", style: .cancel),
                    .init(title: "Add", style: .primary)
                ]
            )
        }
        addButton("Cancel / Destructive (delete chapter)") {
            await Alert.present(
                title: "Delete chapter?",
                message: "This removes the downloaded file but keeps your reading progress.",
                actions: [
                    .init(title: "Cancel", style: .cancel),
                    .init(title: "Delete", style: .destructive)
                ]
            )
        }

        addSection("Three actions — vertical layout")
        addButton("Quality picker") {
            await Alert.present(
                title: "Translation quality",
                message: "Higher quality uses more bandwidth and may take longer.",
                actions: [
                    .init(title: "Best (slow)", style: .primary),
                    .init(title: "Balanced", style: .default),
                    .init(title: "Cancel", style: .cancel)
                ]
            )
        }
        addButton("Destructive with siblings") {
            await Alert.present(
                title: "Remove manga from library?",
                message: "You'll lose categories, reading progress, and custom preferences for this title.",
                actions: [
                    .init(title: "Remove and delete files", style: .destructive),
                    .init(title: "Remove only (keep files)", style: .default),
                    .init(title: "Cancel", style: .cancel)
                ]
            )
        }

        addSection("Edge cases")
        addButton("Long title + long message") {
            await Alert.present(
                title: "An unusually long alert title that should wrap to multiple lines without breaking layout",
                message: "And here is a message that goes on and on and on, demonstrating that the multi-line text wrapping inside the alert card works correctly even with verbose explanatory content that designers sometimes pour into modals.",
                actions: [.init(title: "OK", style: .primary)]
            )
        }
        addButton("Message only — no title") {
            await Alert.present(
                title: nil,
                message: "Saved to library.",
                actions: [.init(title: "OK", style: .primary)]
            )
        }
        addButton("Title only — no message") {
            await Alert.present(
                title: "Sync complete",
                message: nil,
                actions: [.init(title: "OK", style: .primary)]
            )
        }

        addSection("Icon variant")
        addButton("Update available — accent") {
            await Alert.present(
                title: "Update available",
                message: "Version 0.3 adds inline translation, dark-mode polish, and faster syncing.",
                icon: UIImage(systemName: "arrow.up.circle.fill"),
                iconTint: Sumi.Color.accent,
                actions: [
                    .init(title: "Later", style: .cancel),
                    .init(title: "Update", style: .primary)
                ]
            )
        }
        addButton("Permission needed — warning") {
            await Alert.present(
                title: "Network permission required",
                message: "The app needs access to the local network to discover nearby servers and download content.",
                icon: UIImage(systemName: "exclamationmark.triangle.fill"),
                iconTint: Sumi.Color.warning,
                actions: [
                    .init(title: "Not now", style: .cancel),
                    .init(title: "Open Settings", style: .primary)
                ]
            )
        }
        addButton("Sync complete — success") {
            await Alert.present(
                title: "Library synced",
                message: "27 manga updated. 312 new chapters across 14 sources.",
                icon: UIImage(systemName: "checkmark.seal.fill"),
                iconTint: Sumi.Color.success,
                actions: [.init(title: "Got it", style: .primary)]
            )
        }
        addButton("Connection failed — danger") {
            await Alert.present(
                title: "Server unreachable",
                message: "Couldn't connect to the local server at 127.0.0.1:8080. Retry, or open settings to change the port.",
                icon: UIImage(systemName: "xmark.octagon.fill"),
                iconTint: Sumi.Color.danger,
                actions: [
                    .init(title: "Settings", style: .default),
                    .init(title: "Retry", style: .primary)
                ]
            )
        }
        addButton("Premium feature — yamabuki gold") {
            await Alert.present(
                title: "Translation Pro",
                message: "Unlock unlimited manga translation, all source languages, and offline OCR for $4.99/month.",
                icon: UIImage(systemName: "crown.fill"),
                iconTint: Sumi.Brand.yamabukiGold,
                actions: [
                    .init(title: "Maybe later", style: .cancel),
                    .init(title: "Try free", style: .primary)
                ]
            )
        }
        addButton("Destructive — icon + danger") {
            await Alert.present(
                title: "Delete all downloads?",
                message: "This frees 2.4 GB but removes 873 cached chapters. Reading progress is preserved.",
                icon: UIImage(systemName: "trash.fill"),
                iconTint: Sumi.Color.danger,
                actions: [
                    .init(title: "Cancel", style: .cancel),
                    .init(title: "Delete", style: .destructive)
                ]
            )
        }
        addTextButton("Icon + text field — add repo with branding") {
            await Alert.presentText(
                title: "Add repository",
                message: "Enter a source index URL.",
                icon: UIImage(systemName: "link.circle.fill"),
                iconTint: Sumi.Color.accent,
                textField: .init(
                    placeholder: "https://...",
                    keyboardType: .URL,
                    autocapitalization: .none
                ),
                actions: [
                    .init(title: "Cancel", style: .cancel),
                    .init(title: "Add", style: .primary)
                ]
            )
        }

        addSection("Text input variant")
        addTextButton("Add repository URL — URL keyboard") {
            await Alert.presentText(
                title: "Add repository",
                message: "Enter a source index URL.",
                textField: .init(
                    placeholder: "https://...",
                    keyboardType: .URL,
                    autocapitalization: .none
                ),
                actions: [
                    .init(title: "Cancel", style: .cancel),
                    .init(title: "Add", style: .primary)
                ]
            )
        }
        addTextButton("Rename chapter — prefilled initial value") {
            await Alert.presentText(
                title: "Rename chapter",
                message: nil,
                textField: .init(
                    initialValue: "Chapter 142 — The Final Stand",
                    autocapitalization: .sentences
                ),
                actions: [
                    .init(title: "Cancel", style: .cancel),
                    .init(title: "Save", style: .primary)
                ]
            )
        }
        addTextButton("New category — title-only header") {
            await Alert.presentText(
                title: "New category",
                message: nil,
                textField: .init(
                    placeholder: "Category name",
                    autocapitalization: .words
                ),
                actions: [
                    .init(title: "Cancel", style: .cancel),
                    .init(title: "Create", style: .primary)
                ]
            )
        }
        addTextButton("Confirm delete with name") {
            await Alert.presentText(
                title: "Type the manga title to confirm",
                message: "This removes ‘Tokyo Ghoul’ and all 144 downloaded chapters. Cannot be undone.",
                textField: .init(
                    placeholder: "Tokyo Ghoul",
                    autocapitalization: .none
                ),
                actions: [
                    .init(title: "Cancel", style: .cancel),
                    .init(title: "Delete", style: .destructive)
                ]
            )
        }
        addTextButton("Secure password entry") {
            await Alert.presentText(
                title: "Enter password",
                message: "Required to unlock the protected category.",
                textField: .init(
                    placeholder: "Password",
                    keyboardType: .default,
                    autocapitalization: .none,
                    isSecure: true
                ),
                actions: [
                    .init(title: "Cancel", style: .cancel),
                    .init(title: "Unlock", style: .primary)
                ]
            )
        }

        addSection("Multi-text-field (form)")
        addFormButton("Login — username + password") {
            await Alert.presentForm(
                title: "Sign in to repository",
                message: "Some private repos require authentication.",
                icon: UIImage(systemName: "lock.shield.fill"),
                iconTint: Sumi.Color.accent,
                textFields: [
                    .init(placeholder: "Username", autocapitalization: .none),
                    .init(placeholder: "Password", autocapitalization: .none, isSecure: true)
                ],
                actions: [
                    .init(title: "Cancel", style: .cancel),
                    .init(title: "Sign in", style: .primary)
                ]
            )
        }
        addFormButton("Rename — title + description") {
            await Alert.presentForm(
                title: "Rename category",
                message: nil,
                textFields: [
                    .init(initialValue: "Favorites", autocapitalization: .words),
                    .init(placeholder: "Description (optional)", autocapitalization: .sentences)
                ],
                actions: [
                    .init(title: "Cancel", style: .cancel),
                    .init(title: "Save", style: .primary)
                ]
            )
        }

        addSection("Toggle / checkbox")
        addToggleButton("Remove + optional delete downloads") {
            await Alert.presentWithToggles(
                title: "Remove from library?",
                message: "Reading progress is preserved.",
                toggles: [
                    .init(id: "deleteDownloads", label: "Also delete 873 downloaded chapters", initial: true),
                    .init(id: "clearProgress", label: "Reset reading progress", initial: false)
                ],
                actions: [
                    .init(title: "Cancel", style: .cancel),
                    .init(title: "Remove", style: .destructive)
                ]
            )
        }
        addToggleButton("Sign out + cache wipe option") {
            await Alert.presentWithToggles(
                title: "Sign out?",
                message: nil,
                icon: UIImage(systemName: "rectangle.portrait.and.arrow.right"),
                iconTint: Sumi.Color.warning,
                toggles: [
                    .init(id: "clearCache", label: "Clear cached data", initial: false)
                ],
                actions: [
                    .init(title: "Cancel", style: .cancel),
                    .init(title: "Sign out", style: .destructive)
                ]
            )
        }

        addSection("Stepper")
        addStepperButton("Prefetch chapter count") {
            await Alert.presentStepper(
                title: "Prefetch chapters",
                message: "Cache the next N chapters automatically.",
                icon: UIImage(systemName: "arrow.down.circle"),
                iconTint: Sumi.Color.accent,
                stepper: .init(range: 0...10, step: 1, initial: 3, suffix: "chapters"),
                actions: [
                    .init(title: "Cancel", style: .cancel),
                    .init(title: "Save", style: .primary)
                ]
            )
        }
        addStepperButton("Reader brightness") {
            await Alert.presentStepper(
                title: "Brightness",
                message: nil,
                stepper: .init(range: 0...100, step: 5, initial: 70, suffix: "%"),
                actions: [
                    .init(title: "Cancel", style: .cancel),
                    .init(title: "Set", style: .primary)
                ]
            )
        }

        addSection("Expandable details")
        addButton("Update failed — with traceback") {
            await Alert.presentExpandable(
                title: "Update failed",
                message: "Couldn't fetch the latest manga list. The server returned an unexpected response.",
                icon: UIImage(systemName: "exclamationmark.circle.fill"),
                iconTint: Sumi.Color.danger,
                details: """
                URL: https://api.example.com/v1/series?sort=latest
                Status: 500 Internal Server Error
                Time: 2026-05-15 21:03:14

                Request failed after 3 retries.
                The response body was empty or malformed.
                Trace-ID: 9f2c-44a1-bd07-12e8
                """,
                actions: [
                    .init(title: "Cancel", style: .cancel),
                    .init(title: "Retry", style: .primary)
                ]
            )
        }

        addSection("Hold-to-confirm")
        addHoldButton("Delete entire library") {
            await Alert.presentHoldToConfirm(
                title: "Delete entire library?",
                message: "All manga, all downloads, all reading progress. Permanent.",
                icon: UIImage(systemName: "trash.fill"),
                iconTint: Sumi.Color.danger,
                holdAction: .init(title: "Delete", duration: 1.5, style: .destructive),
                cancelTitle: "Cancel"
            )
        }
        addHoldButton("Factory reset — no cancel button") {
            await Alert.presentHoldToConfirm(
                title: "Factory reset",
                message: "Reset the app to its default state. All settings wiped.",
                holdAction: .init(title: "Reset", duration: 2.0, style: .destructive),
                cancelTitle: nil
            )
        }

        addSection("Async action")
        addButton("Validate URL before adding") {
            await Alert.present(
                title: "Add repository",
                message: "Validates the URL by fetching its index before adding.",
                actions: [
                    .init(title: "Cancel", style: .cancel),
                    .init(title: "Add", style: .primary, asyncHandler: {
                        // Simulate ~1.2 s of network work, then succeed.
                        try await Task.sleep(nanoseconds: 1_200_000_000)
                    })
                ]
            )
        }
        addButton("Async that throws — shows inline error") {
            await Alert.present(
                title: "Save changes",
                message: "Attempts to save; the demo fails to show the error path.",
                actions: [
                    .init(title: "Cancel", style: .cancel),
                    .init(title: "Save", style: .primary, asyncHandler: {
                        try await Task.sleep(nanoseconds: 800_000_000)
                        throw DemoError.simulatedFailure
                    })
                ]
            )
        }

        addSection("Progress alert")
        addButton("Spinner — indeterminate") {
            return await Self.runProgressAlertDemo(mode: .indeterminate, cancellable: false)
        }
        addButton("Ring — determinate, animates 0 → 100%") {
            return await Self.runProgressAlertDemo(mode: .determinate, cancellable: false)
        }
        addButton("Cancellable progress (Cancel button)") {
            return await Self.runProgressAlertDemo(mode: .indeterminate, cancellable: true)
        }

        addSection("Markdown — bold / italic / code / link")
        addButton("Download failed — bold count + code IP") {
            return await Alert.present(
                title: "Download failed",
                message: .markdown("Failed to download **3 chapters**. The server at `127.0.0.1:8080` is not responding."),
                actions: [
                    .init(title: "OK", style: .primary)
                ]
            )
        }
        addButton("Tap-able link — opens privacy page") {
            return await Alert.present(
                title: "Continue?",
                message: .markdown("By continuing you agree to the [Terms of Service](https://example.com/terms) and [Privacy Policy](https://example.com/privacy)."),
                linkHandler: { url in
                    print("[Alert] Link tapped: \(url)")
                },
                actions: [
                    .init(title: "Cancel", style: .cancel),
                    .init(title: "Agree", style: .primary)
                ]
            )
        }
        addButton("Mixed markup — italic + code + bold") {
            return await Alert.present(
                title: "Version mismatch",
                message: .markdown("The package `com.example.reader` reports version **2.0.4** but your installed copy is *1.9.7*. Update to sync."),
                actions: [
                    .init(title: "Later", style: .cancel),
                    .init(title: "Reinstall", style: .primary)
                ]
            )
        }

        addSection("Table content — key/value")
        addButton("Manga details — 4 rows") {
            let table = SumiTableView(rows: [
                .init(label: "Source", value: .plain("Inkwell")),
                .init(label: "Pages", value: .plain("24")),
                .init(label: "Language", value: .plain("English")),
                .init(label: "Updated", value: .plain("2 days ago"))
            ])
            return await Alert.present(
                title: "Chapter 47",
                message: "Add to library?",
                customContent: table,
                actions: [
                    .init(title: "Cancel", style: .cancel),
                    .init(title: "Add", style: .primary)
                ]
            )
        }
        addButton("Table with icon rows + bold values") {
            let table = SumiTableView(rows: [
                .init(label: "Name", value: .markdown("**Inkwell**"), icon: UIImage(systemName: "doc.text")),
                .init(label: "Version", value: .markdown("`1.2.3`"), icon: UIImage(systemName: "number")),
                .init(label: "Titles", value: .plain("842"), icon: UIImage(systemName: "books.vertical")),
                .init(label: "Repository", value: .markdown("[github.com/example/inkwell](https://github.com/example/inkwell)"), icon: UIImage(systemName: "link"))
            ])
            table.onLinkTap = { url in
                print("[Alert/Table] Link tapped: \(url)")
            }
            return await Alert.present(
                title: "Catalog installed",
                message: nil,
                customContent: table,
                actions: [
                    .init(title: "Done", style: .primary)
                ]
            )
        }

        addSection("Custom content slot — arbitrary UIView")
        addButton("Cover preview (UIImageView swatch)") {
            return await Alert.present(
                title: "Replace cover?",
                message: "The new cover will be applied across your library.",
                customContent: Self.makeCoverPreview(),
                actions: [
                    .init(title: "Cancel", style: .cancel),
                    .init(title: "Replace", style: .primary)
                ]
            )
        }
    }

    /// Demo runner — walks 1…100 with 25 ms tick (~2.5 s total)
    /// for smooth 1% ring increments. Message line throttled to
    /// every 10% so the crossfade doesn't smear.
    @MainActor
    private static func runProgressAlertDemo(
        mode: SumiProgressAlert.Mode,
        cancellable: Bool
    ) async -> Alert.Action? {
        let total = 100
        let progress = SumiProgressAlert(
            title: mode == .determinate ? "Downloading chapters" : "Refreshing library",
            message: "0 of \(total)",
            mode: mode,
            cancellable: cancellable
        )
        let cancelled = CancellationFlag()
        if cancellable {
            progress.onCancel = { cancelled.set() }
        }
        progress.present()
        for i in 1...total {
            try? await Task.sleep(nanoseconds: 25_000_000)
            if cancelled.get() { break }
            progress.updateProgress(Double(i) / Double(total))
            if i % 10 == 0 || i == total {
                progress.update(message: "\(i) of \(total)")
            }
        }
        await progress.dismiss()
        return nil
    }

    @MainActor
    private final class CancellationFlag {
        private var flag = false
        func set() { flag = true }
        func get() -> Bool { flag }
    }

    private enum DemoError: LocalizedError {
        case simulatedFailure
        var errorDescription: String? {
            "Network unreachable. Check connection and try again."
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

    private func addButton(_ title: String, action: @escaping () async -> Alert.Action?) {
        let button = PlaygroundButtonRow(title: title, accent: Sumi.Color.accent)
        button.onTap = { [weak self] in
            Task { @MainActor in
                let picked = await action()
                self?.statusLabel.status = picked?.title ?? "dismissed"
            }
        }
        stack.addArrangedSubview(button)
    }

    private func addTextButton(_ title: String, action: @escaping () async -> Alert.TextPick?) {
        let button = PlaygroundButtonRow(title: title, accent: Sumi.Color.accent)
        button.onTap = { [weak self] in
            Task { @MainActor in
                let picked = await action()
                if let picked {
                    self?.statusLabel.status = "\(picked.action.title): ‘\(picked.text)’"
                } else {
                    self?.statusLabel.status = "dismissed"
                }
            }
        }
        stack.addArrangedSubview(button)
    }

    private func addFormButton(_ title: String, action: @escaping () async -> Alert.FormPick?) {
        let button = PlaygroundButtonRow(title: title, accent: Sumi.Color.accent)
        button.onTap = { [weak self] in
            Task { @MainActor in
                let picked = await action()
                if let picked {
                    let joined = picked.values.joined(separator: " / ")
                    self?.statusLabel.status = "\(picked.action.title): [\(joined)]"
                } else {
                    self?.statusLabel.status = "dismissed"
                }
            }
        }
        stack.addArrangedSubview(button)
    }

    private func addToggleButton(_ title: String, action: @escaping () async -> Alert.TogglePick?) {
        let button = PlaygroundButtonRow(title: title, accent: Sumi.Color.accent)
        button.onTap = { [weak self] in
            Task { @MainActor in
                let picked = await action()
                if let picked {
                    let on = picked.toggles.filter { $0.value }.map { $0.key }
                    self?.statusLabel.status = "\(picked.action.title) · toggles on: \(on.isEmpty ? "none" : on.joined(separator: ", "))"
                } else {
                    self?.statusLabel.status = "dismissed"
                }
            }
        }
        stack.addArrangedSubview(button)
    }

    private func addStepperButton(_ title: String, action: @escaping () async -> Alert.StepperPick?) {
        let button = PlaygroundButtonRow(title: title, accent: Sumi.Color.accent)
        button.onTap = { [weak self] in
            Task { @MainActor in
                let picked = await action()
                if let picked {
                    self?.statusLabel.status = "\(picked.action.title) → \(picked.value)"
                } else {
                    self?.statusLabel.status = "dismissed"
                }
            }
        }
        stack.addArrangedSubview(button)
    }

    /// Side-by-side cover swatch — stand-in for "old cover vs
    /// new cover" preview. Demonstrates the customContent slot
    /// with non-text content (an arbitrary UIView).
    private static func makeCoverPreview() -> UIView {
        let container = UIView()
        container.translatesAutoresizingMaskIntoConstraints = false

        let oldCover = UIView()
        oldCover.backgroundColor = UIColor(red: 0.32, green: 0.18, blue: 0.10, alpha: 1)
        oldCover.layer.cornerRadius = 10
        oldCover.layer.cornerCurve = .continuous
        oldCover.translatesAutoresizingMaskIntoConstraints = false

        let newCover = UIView()
        newCover.backgroundColor = Sumi.Color.accent
        newCover.layer.cornerRadius = 10
        newCover.layer.cornerCurve = .continuous
        newCover.translatesAutoresizingMaskIntoConstraints = false

        let arrow = UIImageView(image: UIImage(systemName: "arrow.right"))
        arrow.tintColor = Sumi.Color.textTertiary
        arrow.contentMode = .scaleAspectFit
        arrow.translatesAutoresizingMaskIntoConstraints = false

        container.addSubview(oldCover)
        container.addSubview(arrow)
        container.addSubview(newCover)

        NSLayoutConstraint.activate([
            container.heightAnchor.constraint(equalToConstant: 120),

            oldCover.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 20),
            oldCover.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            oldCover.widthAnchor.constraint(equalToConstant: 80),
            oldCover.heightAnchor.constraint(equalToConstant: 110),

            arrow.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            arrow.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            arrow.widthAnchor.constraint(equalToConstant: 22),

            newCover.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -20),
            newCover.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            newCover.widthAnchor.constraint(equalToConstant: 80),
            newCover.heightAnchor.constraint(equalToConstant: 110)
        ])
        return container
    }

    private func addHoldButton(_ title: String, action: @escaping () async -> Bool) {
        let button = PlaygroundButtonRow(title: title, accent: Sumi.Color.danger)
        button.onTap = { [weak self] in
            Task { @MainActor in
                let confirmed = await action()
                self?.statusLabel.status = confirmed ? "CONFIRMED (held to completion)" : "cancelled"
            }
        }
        stack.addArrangedSubview(button)
    }
}
