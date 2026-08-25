# Lucid Logical Machine Demo

Small SwiftUI chat application that runs a quantized GGUF language model locally through llama.cpp in the iOS Simulator.

## Requirements

- Apple Silicon Mac
- Xcode with an iOS Simulator runtime
- The llama.cpp `llama.xcframework` referenced by the Xcode project
- A valid instruct GGUF model (the automatic path uses the configured ModelScope model)

The simulator is useful for functional development only. It does not represent iPhone GPU, Neural Engine, thermal, battery, or performance behavior.

## Run

Build the simulator target:

```bash
xcodebuild -project LucidLogicalMachineDemo.xcodeproj \
  -scheme LucidLogicalMachineDemo \
  -sdk iphonesimulator \
  -configuration Debug \
  build CODE_SIGNING_ALLOWED=NO
```

Run the app, then select **Load Model**. A local `.gguf` in the simulator container’s `Documents/Models` directory is used first. If none exists, the app attempts the configured HTTPS ModelScope download and validates its size and SHA-256 checksum.

For UI work without model weights, add `MOCK_LLM` to **Build Settings > Swift Active Compilation Conditions**. Responses then come from `MockLLMService`.

## Architecture

```text
SwiftUI ChatView
  -> ChatViewModel (@MainActor)
    -> LLMService
      -> LlamaCppService or MockLLMService
```

`LlamaCppService` owns the native model/context/sampler lifecycle and streams generated fragments. `ModelStore` handles model discovery, download, temporary files, and integrity checks. `PromptGuard` rejects prompts that exceed the small model’s budget or require unavailable tools/current information. The UI displays an estimated 2,048-token context window.

## Limitations

- The demo uses a 2,048-token context and a dynamic maximum of 256 generated tokens.
- The context gauge is an estimate based on message text.
- Simulator inference uses CPU layers because simulator Metal does not support the required residency sets.
- The current instruct prompt supports concise answers but is not a substitute for factual verification.
- Do not commit model weights, credentials, or private model URLs.
