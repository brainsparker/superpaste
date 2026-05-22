import Foundation

/// Static catalog of vision-language models SuperPaste supports.
///
/// The list is intentionally short — three tiers covering the practical Apple Silicon
/// memory bands (8GB / 16GB / 32GB+). Users pick one during onboarding and can switch
/// later in Settings.
///
/// Sizes are uncompressed weights on disk; resident RAM is roughly weights + KV cache
/// + working set. Numbers come from `mlx-community` quantizations as of 2026-05.
enum ModelCatalog {

    struct Model: Identifiable, Equatable, Hashable {
        /// Stable, URL-safe identifier — also the on-disk folder name.
        let id: String
        /// Display name shown in the picker.
        let displayName: String
        /// One-line description for the picker.
        let summary: String
        /// HuggingFace repository — the format `loadModelContainer` expects.
        let huggingFaceRepo: String
        /// Approximate download size in bytes.
        let downloadSizeBytes: Int64
        /// Approximate RAM footprint once loaded.
        let residentRAMBytes: Int64
        /// Recommended minimum physical RAM on the user's Mac to install this model.
        let minSystemRAMBytes: Int64
        /// Marker for the default selection in onboarding.
        let isRecommended: Bool

        var downloadSizeLabel: String {
            ByteCountFormatter.string(fromByteCount: downloadSizeBytes, countStyle: .file)
        }

        var residentRAMLabel: String {
            ByteCountFormatter.string(fromByteCount: residentRAMBytes, countStyle: .memory)
        }
    }

    static let all: [Model] = [
        Model(
            id: "smolvlm-instruct-4bit",
            displayName: "SmolVLM",
            summary: "Small and fast. Best for 8GB Macs.",
            huggingFaceRepo: "mlx-community/SmolVLM-Instruct-4bit",
            downloadSizeBytes: 400_000_000,
            residentRAMBytes: 700_000_000,
            minSystemRAMBytes: 8_000_000_000,
            isRecommended: false
        ),
        Model(
            id: "qwen25-vl-3b-instruct-4bit",
            displayName: "Qwen 2.5 VL 3B",
            summary: "Balanced quality and speed. Recommended.",
            huggingFaceRepo: "mlx-community/Qwen2.5-VL-3B-Instruct-4bit",
            downloadSizeBytes: 2_000_000_000,
            residentRAMBytes: 2_200_000_000,
            minSystemRAMBytes: 16_000_000_000,
            isRecommended: true
        ),
        Model(
            id: "qwen25-vl-7b-instruct-4bit",
            displayName: "Qwen 2.5 VL 7B",
            summary: "Highest quality. For 32GB+ Macs.",
            huggingFaceRepo: "mlx-community/Qwen2.5-VL-7B-Instruct-4bit",
            downloadSizeBytes: 4_500_000_000,
            residentRAMBytes: 5_000_000_000,
            minSystemRAMBytes: 32_000_000_000,
            isRecommended: false
        )
    ]

    static var recommended: Model {
        all.first(where: \.isRecommended) ?? all[0]
    }

    static func model(withId id: String) -> Model? {
        all.first { $0.id == id }
    }
}
