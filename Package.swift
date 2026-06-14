// swift-tools-version: 5.9
import PackageDescription

// Sumi — a manga-inspired UIKit design system.
//
// Single pure-SPM package. Components are consumed individually
// — `import SumiAlert` only pulls in the alert and its
// dependencies, so a consumer never drags in chrome it doesn't
// use.
//
// Two-layer architecture:
//
//   Sumi target       — design tokens (Brand + Semantic + Shadow
//                       + Typography + Spacing + Radius + Motion).
//                       Every component depends on this.
//
//   Sumi<Name> target — concrete components. Self-contained, each
//                       only depends on Sumi (and SumiMenuKit if
//                       it's menu-related shared infra).
//
//   SumiMenuKit       — shared infrastructure for menu components
//                       (SumiMenu + SumiContextMenu use identical
//                       action-row and list views).
//
// Public/internal boundary: every target's public surface is the
// API consumers use. Anything not `public` is implementation
// detail and can change freely.

// Per-target Swift settings. Kept empty on purpose: warnings-as-
// errors is enforced in CI (via xcodebuild flags), NOT baked into
// the manifest. SwiftPM forbids `unsafeFlags` in any package
// consumed through a version requirement, so a clean manifest is
// what lets Sumi be used as a normal versioned dependency.
let warningsAsErrors: [SwiftSetting] = []

let package = Package(
    name: "Sumi",
    defaultLocalization: "en",
    platforms: [
        // iOS 13 is the floor: async/await (Swift 5.5+),
        // `cornerCurve`, `UIImage(systemName:)`, dynamic-provider
        // colours, withCheckedContinuation — all introduced in 13.
        // Nothing in Sumi uses an iOS 14+ API; lowering further
        // would mean rewriting the touch overlays + symbol icons.
        .iOS(.v13)
    ],
    products: [
        .library(name: "Sumi", targets: ["Sumi"]),
        .library(name: "SumiToast", targets: ["SumiToast"]),
        .library(name: "SumiAlert", targets: ["SumiAlert"]),
        .library(name: "SumiMenuKit", targets: ["SumiMenuKit"]),
        .library(name: "SumiMenu", targets: ["SumiMenu"]),
        .library(name: "SumiContextMenu", targets: ["SumiContextMenu"]),
        .library(name: "SumiPicker", targets: ["SumiPicker"]),
        .library(name: "SumiSheet", targets: ["SumiSheet"]),
        .library(name: "SumiDialog", targets: ["SumiDialog"]),
        .library(name: "SumiStepper", targets: ["SumiStepper"]),
        .library(name: "SumiTable", targets: ["SumiTable"]),
    ],
    dependencies: [
        // Sumi ships with ZERO external runtime dependencies, so
        // a consumer's package graph stays clean.
        //
        // Snapshot tests are intentionally kept out of this
        // manifest: their transitive dev graph (CustomDump, etc.)
        // shouldn't be visible to consumers. When re-enabled they
        // live in a separate `SumiTests/Package.swift`.
    ],
    targets: [
        // ---------------- foundation ----------------
        .target(
            name: "Sumi",
            swiftSettings: warningsAsErrors
        ),

        // ---------------- shared infrastructure ----------------
        // Action item + reusable list view (with blur, separators,
        // press states). Both `SumiMenu` and `SumiContextMenu`
        // depend on this so they share an identical visual
        // language.
        .target(
            name: "SumiMenuKit",
            dependencies: ["Sumi"],
            swiftSettings: warningsAsErrors
        ),

        // ---------------- concrete components ----------------
        .target(
            name: "SumiToast",
            dependencies: ["Sumi"],
            swiftSettings: warningsAsErrors
        ),
        .target(
            name: "SumiAlert",
            dependencies: ["Sumi"],
            swiftSettings: warningsAsErrors
        ),
        .target(
            name: "SumiMenu",
            dependencies: ["Sumi", "SumiMenuKit"],
            swiftSettings: warningsAsErrors
        ),
        .target(
            name: "SumiContextMenu",
            dependencies: ["Sumi", "SumiMenuKit"],
            swiftSettings: warningsAsErrors
        ),
        .target(
            name: "SumiPicker",
            dependencies: ["Sumi"],
            swiftSettings: warningsAsErrors
        ),
        .target(
            name: "SumiSheet",
            dependencies: ["Sumi"],
            swiftSettings: warningsAsErrors
        ),
        .target(
            name: "SumiDialog",
            dependencies: ["Sumi"],
            swiftSettings: warningsAsErrors
        ),
        // Large hero-sized integer stepper card. Designed for
        // SumiDialog `customContent` slots where the
        // adjusted value is the entire interaction surface
        // (chapter count, page limit, day count). Distinct
        // from the standard inline `UIStepper`: 72pt-bold
        // value display + 64pt circular ± buttons + auto-
        // repeat on hold.
        .target(
            name: "SumiStepper",
            dependencies: ["Sumi"],
            swiftSettings: warningsAsErrors
        ),
        .target(
            name: "SumiTable",
            dependencies: ["Sumi"],
            swiftSettings: warningsAsErrors
        ),

        // ---------------- tests ----------------
        // Snapshot tests live in a separate `SumiTests/Package.swift`
        // so their dev-only transitive graph never reaches consumers.
    ]
)
