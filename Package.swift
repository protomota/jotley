// swift-tools-version: 6.0
import PackageDescription
let package = Package(
    name: "jotley",
    platforms: [.macOS("27.0")],
    products: [.library(name: "jotley", targets: ["jotley"])],
    targets: [
        .target(name: "jotley", path: ".", exclude: [
            "AppIcon.icon", "CLAUDE.md", "PROJECT-STRUCTURE.md", "README.md", "LICENSE", "Comfortaa-OFL.txt",
            "Tests", "Sources", "Jotley.xcodeproj", "JotleyUITests-macOS", "Shared/Docs",
            "macOS/Assets.xcassets", "macOS/Preview Content", "macOS/JotleyApp.swift",
            "macOS/Info.plist", "macOS/Jotley.entitlements", "macOS/Jotley-Development.entitlements", "macOS/Config",
            "build", "releases", "backup_20250709_083459", "Jotley", "iOS", "JotleyWidgets",
            "JotleyUITests-iOS", "Jotley-iOSTests", "Jotley-iOSUITests", "OneSignalNotificationServiceExtension", "Installer", "docs",
            "examples", "fastlane", "scripts", "sparkle-keys", "Gemfile.lock"
        ], sources: [
            "Shared/Services/SharedPersistence.swift",
            "Shared/Services/SummarizationService.swift",
            "Shared/Services/TranscriptionService.swift",
            "macOS/ProcessTap/CoreAudioUtils.swift",
            "macOS/ProcessTap/ProcessTap.swift",
            "macOS/ProcessTap/ProcessTapRecorder.swift"
        ], resources: [.process("Shared/Models/JotleyNotes.xcdatamodeld")]),
        .testTarget(name: "jotleyTests", dependencies: ["jotley"], path: "Tests/jotleyTests",
                    sources: ["ContinuationResumerTests.swift"])
    ],
    swiftLanguageModes: [.v5]
)
