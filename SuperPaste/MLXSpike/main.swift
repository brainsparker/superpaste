// MLX VLM latency spike for SuperPaste.
//
// Loads a vision-language model from HuggingFace via mlx-swift-lm, runs a single
// image+prompt round-trip, and prints wall-clock timings for:
//   - first-time download + model load (cold)
//   - inference (warm)
//
// This is the Phase 1 go/no-go gate for the OSS local-pivot. If a 3B 4-bit VLM
// can't get a useful response back in under ~5 seconds on the target Mac, the
// product direction needs to be reconsidered before any further investment.
//
// Usage:
//   swift run -c release MLXSpike \
//       [model-id] [image-path] [prompt]
//
// Defaults:
//   model-id:   mlx-community/Qwen2.5-VL-3B-Instruct-4bit
//   image-path: ./MLXSpike/test.jpg   (provide your own — any screenshot works)
//   prompt:     "Describe what is on screen and suggest an appropriate reply."

import Foundation
import CoreImage
import MLXLMCommon
import MLXVLM
import MLXHuggingFace
import HuggingFace
import Tokenizers

@main
struct MLXSpike {
    static func main() async {
        let args = CommandLine.arguments
        let modelId = args.count > 1 ? args[1] : "mlx-community/Qwen2.5-VL-3B-Instruct-4bit"
        let imagePath = args.count > 2 ? args[2] : "./MLXSpike/test.jpg"
        let prompt = args.count > 3 ? args[3] : "Describe what is on screen and suggest an appropriate reply. Be concise."

        print("=== MLX VLM latency spike ===")
        print("Model:  \(modelId)")
        print("Image:  \(imagePath)")
        print("Prompt: \(prompt)")
        print("")

        let imageURL = URL(fileURLWithPath: imagePath)
        guard FileManager.default.fileExists(atPath: imageURL.path) else {
            fputs("Error: image not found at \(imageURL.path)\n", stderr)
            fputs("Pass an image as the second argument, or drop one at ./MLXSpike/test.jpg\n", stderr)
            exit(1)
        }
        guard let testImage = CIImage(contentsOf: imageURL) else {
            fputs("Error: failed to decode image at \(imageURL.path)\n", stderr)
            exit(1)
        }

        do {
            // ---- Load (cold: includes any HuggingFace download) ----
            print("Loading model… (first run downloads ~2GB to ~/Documents/huggingface)")
            let loadStart = Date()
            let container = try await #huggingFaceLoadModelContainer(
                configuration: ModelConfiguration(id: modelId)
            ) { progress in
                if progress.totalUnitCount > 0 {
                    let pct = Int(progress.fractionCompleted * 100)
                    print("  download: \(pct)%  (\(progress.completedUnitCount) / \(progress.totalUnitCount))")
                }
            }
            let loadSeconds = Date().timeIntervalSince(loadStart)
            print(String(format: "Loaded in %.2fs", loadSeconds))
            print("")

            // ---- Inference (warm) ----
            print("Generating…")
            let session = ChatSession(container)
            let inferStart = Date()
            let answer = try await session.respond(
                to: prompt,
                image: UserInput.Image.ciImage(testImage)
            )
            let inferSeconds = Date().timeIntervalSince(inferStart)

            print("")
            print("--- Response ---")
            print(answer)
            print("---")
            print("")
            print(String(format: "Load:      %.2fs", loadSeconds))
            print(String(format: "Inference: %.2fs   <-- the number that matters for v1", inferSeconds))
            print("")
            if inferSeconds < 3 {
                print("✓ Under 3s — green light.")
            } else if inferSeconds < 5 {
                print("≈ 3–5s — acceptable, watch for regressions.")
            } else if inferSeconds < 8 {
                print("✗ 5–8s — too slow for hotkey-paste UX. Try a smaller model or downscale the image.")
            } else {
                print("✗✗ > 8s — reconsider the architecture before going further.")
            }
            exit(0)
        } catch {
            fputs("Spike failed: \(error)\n", stderr)
            exit(1)
        }
    }
}
