import UIKit
import Sumi
import SumiDialog
import SumiTable

// DialogPlaygroundViewController — exercises every variant of
// `SumiDialog` so the visual + interaction behaviour can be
// poked directly.

@MainActor
public final class DialogPlaygroundViewController: UIViewController {

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
        hint.text = "Material-3-styled dialog with right-aligned text buttons, tap-outside dismiss, and outlined floating-label text field. Use for softer form prompts where iOS-native Alert feels too heavy."
        hint.font = Sumi.Font.caption()
        hint.textColor = Sumi.Color.textSecondary
        hint.numberOfLines = 0
        stack.addArrangedSubview(hint)
        stack.setCustomSpacing(Sumi.Spacing.xl, after: hint)

        addSection("Basic dialog")
        addButton("Two actions — Cancel / OK") {
            await SumiDialog.present(
                title: "Set categories",
                message: "Manga that matches the picked categories will appear in your filtered library views.",
                actions: [
                    .init(title: "Cancel", style: .cancel),
                    .init(title: "OK", style: .primary)
                ]
            )
        }
        addButton("Three actions — Edit / Cancel / OK") {
            await SumiDialog.present(
                title: "Set categories",
                message: nil,
                actions: [
                    .init(title: "Edit", style: .default),
                    .init(title: "Cancel", style: .cancel),
                    .init(title: "OK", style: .primary)
                ]
            )
        }
        addButton("Destructive action") {
            await SumiDialog.present(
                title: "Remove from library?",
                message: "Reading progress is preserved.",
                actions: [
                    .init(title: "Cancel", style: .cancel),
                    .init(title: "Remove", style: .destructive)
                ]
            )
        }
        addButton("Long title + long message") {
            await SumiDialog.present(
                title: "An unusually long dialog title that should wrap to multiple lines",
                message: "And here is a body message that goes on and on, demonstrating that the multi-line text wrapping inside the dialog card works correctly even with verbose explanatory content.",
                actions: [
                    .init(title: "Got it", style: .primary)
                ]
            )
        }

        addSection("Text field styles — A / B test")
        addTextButton("Inset (default) — static label above") {
            await SumiDialog.presentText(
                title: "Add repository",
                message: "Default text field style — static label above, cream-filled inset, iOS-idiomatic.",
                textField: .init(
                    label: "Repo URL",
                    keyboardType: .URL,
                    autocapitalization: .none,
                    isRequired: true,
                    style: .inset
                ),
                actions: [
                    .init(title: "Cancel", style: .cancel),
                    .init(title: "Add", style: .primary)
                ]
            )
        }
        addTextButton("Outlined — Material 3 floating label") {
            await SumiDialog.presentText(
                title: "Add repository",
                message: "Material 3 outlined style — label floats onto the border on focus / fill.",
                textField: .init(
                    label: "Repo URL",
                    keyboardType: .URL,
                    autocapitalization: .none,
                    isRequired: true,
                    style: .outlined
                ),
                actions: [
                    .init(title: "Cancel", style: .cancel),
                    .init(title: "Add", style: .primary)
                ]
            )
        }
        addTextButton("Stamp — manga hanko tag (experimental)") {
            await SumiDialog.presentText(
                title: "Add repository",
                message: "Sumi-unique style — label sits as a small stamp tag in the corner.",
                textField: .init(
                    label: "Repo URL",
                    keyboardType: .URL,
                    autocapitalization: .none,
                    isRequired: true,
                    style: .stamp
                ),
                actions: [
                    .init(title: "Cancel", style: .cancel),
                    .init(title: "Add", style: .primary)
                ]
            )
        }

        addSection("Text input — outlined floating label")
        addTextButton("Add repo — required URL") {
            await SumiDialog.presentText(
                title: "Add repo",
                message: "Add a source repository. Paste a URL ending in \"manifest.json\".",
                textField: .init(
                    label: "Repo URL",
                    keyboardType: .URL,
                    autocapitalization: .none,
                    isRequired: true
                ),
                actions: [
                    .init(title: "Cancel", style: .cancel),
                    .init(title: "Add", style: .primary)
                ]
            )
        }
        addTextButton("Add category — required name") {
            await SumiDialog.presentText(
                title: "Add category",
                message: nil,
                textField: .init(
                    label: "Name",
                    autocapitalization: .words,
                    isRequired: true
                ),
                actions: [
                    .init(title: "Cancel", style: .cancel),
                    .init(title: "Add", style: .primary)
                ]
            )
        }
        addTextButton("Rename — optional, prefilled") {
            await SumiDialog.presentText(
                title: "Rename chapter",
                message: nil,
                textField: .init(
                    label: "Chapter title",
                    initialValue: "Chapter 142 — The Final Stand",
                    autocapitalization: .sentences,
                    isRequired: false
                ),
                actions: [
                    .init(title: "Cancel", style: .cancel),
                    .init(title: "Save", style: .primary)
                ]
            )
        }
        addTextButton("Password — secure entry") {
            await SumiDialog.presentText(
                title: "Enter password",
                message: "Required to unlock the protected category.",
                textField: .init(
                    label: "Password",
                    autocapitalization: .none,
                    isSecure: true,
                    isRequired: true
                ),
                actions: [
                    .init(title: "Cancel", style: .cancel),
                    .init(title: "Unlock", style: .primary)
                ]
            )
        }
        addTextButton("Discard-on-outside (type then tap dimmer)") {
            await SumiDialog.presentText(
                title: "Rename chapter",
                message: "Try typing something, then tap outside the card.",
                textField: .init(
                    label: "Chapter title",
                    autocapitalization: .sentences
                ),
                confirmDiscardIfEdited: true,
                actions: [
                    .init(title: "Cancel", style: .cancel),
                    .init(title: "Save", style: .primary)
                ]
            )
        }

        addSection("Multi-text-field (form)")
        addFormButton("Login — username + password") {
            await SumiDialog.presentForm(
                title: "Sign in to repository",
                message: "Some private repos require authentication.",
                textFields: [
                    .init(label: "Username", autocapitalization: .none, isRequired: true),
                    .init(label: "Password", autocapitalization: .none, isSecure: true, isRequired: true)
                ],
                confirmDiscardIfEdited: true,
                actions: [
                    .init(title: "Cancel", style: .cancel),
                    .init(title: "Sign in", style: .primary)
                ]
            )
        }
        addFormButton("Rename + description") {
            await SumiDialog.presentForm(
                title: "Edit category",
                message: nil,
                textFields: [
                    .init(label: "Name", initialValue: "Favorites", autocapitalization: .words, isRequired: true),
                    .init(label: "Description (optional)", autocapitalization: .sentences)
                ],
                actions: [
                    .init(title: "Cancel", style: .cancel),
                    .init(title: "Save", style: .primary)
                ]
            )
        }

        addSection("Focus trace — magnetic field-line draw-in (experimental)")
        addFormButton("Login — tracing focus (username + password)") {
            await SumiDialog.presentForm(
                title: "Sign in to tracker",
                message: "Watch the accent outline draw in from the top and seal at the bottom as each field focuses. Expert opt-in: `focusAnimation: .tracing`.",
                textFields: [
                    .init(
                        label: "Username",
                        placeholder: "Email or username",
                        autocapitalization: .none,
                        isRequired: true,
                        showsRequiredIndicator: false,
                        style: .inset,
                        focusAnimation: .tracing
                    ),
                    .init(
                        label: "Password",
                        placeholder: "Your password",
                        autocapitalization: .none,
                        isSecure: true,
                        isRequired: true,
                        showsRequiredIndicator: false,
                        style: .inset,
                        focusAnimation: .tracing
                    )
                ],
                actions: [
                    .init(title: "Cancel", style: .cancel),
                    .init(title: "Log in", style: .primary)
                ]
            )
        }
        addTextButton("Single field — tracing focus") {
            await SumiDialog.presentText(
                title: "Add repository",
                message: "Same inset field, focus accent drawn as a magnetic-field trace.",
                textField: .init(
                    label: "Repo URL",
                    placeholder: "https://…/manifest.json",
                    keyboardType: .URL,
                    autocapitalization: .none,
                    isRequired: true,
                    style: .inset,
                    focusAnimation: .tracing
                ),
                actions: [
                    .init(title: "Cancel", style: .cancel),
                    .init(title: "Add", style: .primary)
                ]
            )
        }

        addSection("Icon banner")
        addButton("Warning — permission needed") {
            await SumiDialog.present(
                title: "Network permission required",
                message: "The app needs access to the local network to discover nearby servers.",
                icon: UIImage(systemName: "wifi.exclamationmark"),
                iconTint: Sumi.Color.warning,
                actions: [
                    .init(title: "Not now", style: .cancel),
                    .init(title: "Open Settings", style: .primary)
                ]
            )
        }
        addButton("Success — sync complete") {
            await SumiDialog.present(
                title: "Library synced",
                message: "27 manga updated · 312 new chapters",
                icon: UIImage(systemName: "checkmark.seal.fill"),
                iconTint: Sumi.Color.success,
                actions: [.init(title: "OK", style: .primary)]
            )
        }
        addButton("Danger — destructive confirm") {
            await SumiDialog.present(
                title: "Delete library?",
                message: "All manga, all downloads, all progress. Cannot be undone.",
                icon: UIImage(systemName: "trash.fill"),
                iconTint: Sumi.Color.danger,
                actions: [
                    .init(title: "Cancel", style: .cancel),
                    .init(title: "Delete", style: .destructive)
                ]
            )
        }

        addSection("Async action")
        addTextButton("Add repo — validate URL (succeeds)") {
            await SumiDialog.presentText(
                title: "Add repository",
                message: "Validates the URL by fetching its index before adding.",
                textField: .init(label: "Repo URL", keyboardType: .URL, autocapitalization: .none, isRequired: true),
                actions: [
                    .init(title: "Cancel", style: .cancel),
                    .init(title: "Add", style: .primary, asyncHandler: {
                        try await Task.sleep(nanoseconds: 1_200_000_000)
                    })
                ]
            )
        }
        addTextButton("Add repo — validate URL (fails)") {
            await SumiDialog.presentText(
                title: "Add repository",
                message: "Demo of error path — validation throws.",
                textField: .init(label: "Repo URL", keyboardType: .URL, autocapitalization: .none, isRequired: true),
                actions: [
                    .init(title: "Cancel", style: .cancel),
                    .init(title: "Add", style: .primary, asyncHandler: {
                        try await Task.sleep(nanoseconds: 900_000_000)
                        throw DemoDialogError.serverUnreachable
                    })
                ]
            )
        }

        addSection("Progress dialog")
        addButton("Spinner — indeterminate, auto-completes") {
            return await Self.runMigrationDemo(mode: .indeterminate, cancellable: false)
        }
        addButton("Spinner — indeterminate, cancellable") {
            return await Self.runMigrationDemo(mode: .indeterminate, cancellable: true)
        }
        addButton("Ring — determinate, animates 0 → 100%") {
            return await Self.runMigrationDemo(mode: .determinate, cancellable: false)
        }
        addButton("Ring — determinate, cancellable") {
            return await Self.runMigrationDemo(mode: .determinate, cancellable: true)
        }

        addSection("Image preview")
        addButton("Replace cover? — with preview") {
            await SumiDialog.present(
                title: "Replace cover?",
                message: "This will use the new cover image for Tokyo Ghoul across your library.",
                image: Self.makeDemoCover(),
                actions: [
                    .init(title: "Cancel", style: .cancel),
                    .init(title: "Replace", style: .primary)
                ]
            )
        }
        addTextButton("Rename with cover preview") {
            await SumiDialog.presentText(
                title: "Rename manga",
                message: nil,
                image: Self.makeDemoCover(),
                textField: .init(
                    label: "Title",
                    initialValue: "Tokyo Ghoul",
                    autocapitalization: .words
                ),
                actions: [
                    .init(title: "Cancel", style: .cancel),
                    .init(title: "Save", style: .primary)
                ]
            )
        }

        addSection("Markdown — bold / italic / code / link")
        addButton("Download failed — bold count + code IP") {
            return await SumiDialog.present(
                title: "Download failed",
                message: .markdown("Failed to download **3 chapters**. The server at `127.0.0.1:8080` is not responding."),
                actions: [
                    .init(title: "OK", style: .primary)
                ]
            )
        }
        addButton("Tap-able link — opens privacy page") {
            return await SumiDialog.present(
                title: "Continue?",
                message: .markdown("By continuing you agree to the [Terms of Service](https://example.com/terms) and [Privacy Policy](https://example.com/privacy)."),
                linkHandler: { url in
                    print("[Dialog] Link tapped: \(url)")
                },
                actions: [
                    .init(title: "Cancel", style: .cancel),
                    .init(title: "Agree", style: .primary)
                ]
            )
        }
        addButton("Mixed markup with icon banner") {
            return await SumiDialog.present(
                title: "Update available",
                message: .markdown("Version **2.1.0** is ready. Includes *47 fixes* and a new `sync` engine."),
                icon: UIImage(systemName: "arrow.down.app.fill"),
                iconTint: Sumi.Color.accent,
                actions: [
                    .init(title: "Later", style: .cancel),
                    .init(title: "Update", style: .primary)
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
            return await SumiDialog.present(
                title: "Chapter 47",
                message: "Add to library?",
                customContent: table,
                actions: [
                    .init(title: "Cancel", style: .cancel),
                    .init(title: "Add", style: .primary)
                ]
            )
        }
        addButton("Catalog info — icons + bold + link") {
            let table = SumiTableView(rows: [
                .init(label: "Name", value: .markdown("**Inkwell**"), icon: UIImage(systemName: "doc.text")),
                .init(label: "Version", value: .markdown("`1.2.3`"), icon: UIImage(systemName: "number")),
                .init(label: "Titles", value: .plain("842"), icon: UIImage(systemName: "books.vertical")),
                .init(label: "Repository", value: .markdown("[github.com/example/inkwell](https://github.com/example/inkwell)"), icon: UIImage(systemName: "link"))
            ])
            table.onLinkTap = { url in
                print("[Dialog/Table] Link tapped: \(url)")
            }
            return await SumiDialog.present(
                title: "Catalog installed",
                message: nil,
                customContent: table,
                actions: [
                    .init(title: "Done", style: .primary)
                ]
            )
        }
    }

    private enum DemoDialogError: LocalizedError {
        case serverUnreachable
        var errorDescription: String? {
            "Couldn't reach the server. Check the URL and try again."
        }
    }

    /// Demo migration: walks 1…100 with 25 ms per step — smooth
    /// 1% increments rather than 10% jumps so the ring animates
    /// like a real download (~2.5 s total). For `.indeterminate`
    /// mode the spinner just runs and the message updates with
    /// coarser granularity. Returns the resulting action (always
    /// nil for progress — there's no user pick to return).
    @MainActor
    private static func runMigrationDemo(
        mode: SumiProgressDialog.Mode,
        cancellable: Bool
    ) async -> SumiDialog.Action? {
        let total = 100
        let progress = SumiProgressDialog(
            title: mode == .determinate ? "Downloading chapters" : "Migrating library...",
            message: "0 of \(total) manga processed",
            mode: mode,
            cancellable: cancellable
        )
        let cancelled = CancellationFlag()
        if cancellable {
            progress.onCancel = {
                cancelled.set()
            }
        }
        progress.present()
        for i in 1...total {
            try? await Task.sleep(nanoseconds: 25_000_000)
            if cancelled.get() { break }
            progress.updateProgress(Double(i) / Double(total))
            // Throttle the text crossfade — every tick (25 ms)
            // would overlap the 180 ms animation into garbage.
            // Updating each 10 % is readable AND aligned with
            // how a real downloader reports progress in batches.
            if i % 10 == 0 || i == total {
                progress.update(message: "\(i) of \(total) manga processed")
            }
        }
        await progress.dismiss()
        return nil
    }

    /// Simple boxed Bool for cancellation signalling between
    /// the demo's progress loop and the dialog's `onCancel`
    /// callback. (Real code would use Task cancellation.)
    @MainActor
    private final class CancellationFlag {
        private var flag = false
        func set() { flag = true }
        func get() -> Bool { flag }
    }

    /// Solid-colour swatch as a stand-in manga cover for the
    /// image-preview demos. A host app would pass a downloaded
    /// thumbnail UIImage here.
    private static func makeDemoCover() -> UIImage {
        let size = CGSize(width: 240, height: 320)
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { context in
            UIColor(red: 0.78, green: 0.29, blue: 0.18, alpha: 1).setFill()
            context.fill(CGRect(origin: .zero, size: size))
            let attrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 24, weight: .bold),
                .foregroundColor: UIColor.white
            ]
            let text = "東京喰種" as NSString
            let textSize = text.size(withAttributes: attrs)
            text.draw(
                at: CGPoint(x: (size.width - textSize.width) / 2, y: (size.height - textSize.height) / 2),
                withAttributes: attrs
            )
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

    private func addButton(_ title: String, action: @escaping () async -> SumiDialog.Action?) {
        let button = PlaygroundButtonRow(title: title, accent: Sumi.Color.accent)
        button.onTap = { [weak self] in
            Task { @MainActor in
                let picked = await action()
                self?.statusLabel.status = picked?.title ?? "dismissed"
            }
        }
        stack.addArrangedSubview(button)
    }

    private func addTextButton(_ title: String, action: @escaping () async -> SumiDialog.TextPick?) {
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

    private func addFormButton(_ title: String, action: @escaping () async -> SumiDialog.FormPick?) {
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
}
