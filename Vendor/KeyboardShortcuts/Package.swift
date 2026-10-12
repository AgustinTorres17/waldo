// swift-tools-version:6.2
import PackageDescription

// Vendored copy of sindresorhus/KeyboardShortcuts 3.1.0 (MIT, see license), so
// Waldo builds with Command Line Tools alone. Changes are marked "Waldo patch":
// no SwiftUI macros (`@Entry`, `#Preview` need Xcode's plugins) and the resource
// bundle is looked up in Contents/Resources. Docs and tests were dropped.
let package = Package(
	name: "KeyboardShortcuts",
	defaultLocalization: "en",
	platforms: [
		.macOS(.v10_15)
	],
	products: [
		.library(
			name: "KeyboardShortcuts",
			targets: [
				"KeyboardShortcuts"
			]
		)
	],
	targets: [
		.target(
			name: "KeyboardShortcuts",
			swiftSettings: [
				.defaultIsolation(MainActor.self),
				.enableUpcomingFeature("NonisolatedNonsendingByDefault"),
				.enableUpcomingFeature("InferIsolatedConformances")
			]
		)
	]
)
