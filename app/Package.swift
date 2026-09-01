// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "RecordTranscriber",
    platforms: [.macOS("14.4")],
    targets: [
        .executableTarget(
            name: "RecordTranscriber",
            path: "Sources/RecordTranscriber",
            // Swift 5 language mode: the audio callback shares preallocated
            // buffers with the encoder thread by design, which strict
            // concurrency checking cannot express without wrapping every audio
            // type in an unchecked-Sendable box.
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "RecordTranscriberTests",
            dependencies: ["RecordTranscriber"],
            path: "Tests/RecordTranscriberTests",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
