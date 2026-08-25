# Copilot instructions

## Build and validation

The repository contains one Xcode project and one application scheme:

```bash
xcodebuild -project LucidLogicalMachineDemo.xcodeproj \
  -scheme LucidLogicalMachineDemo \
  -sdk iphonesimulator \
  -configuration Debug \
  build CODE_SIGNING_ALLOWED=NO
```

There is currently no XCTest target or lint configuration. Validate changes with the simulator build above. If a test target is added, run a single test with:

```bash
xcodebuild test \
  -project LucidLogicalMachineDemo.xcodeproj \
  -scheme LucidLogicalMachineDemo \
  -destination 'platform=iOS Simulator,name=<installed-iPhone>,OS=<installed-version>' \
  -only-testing:LucidLogicalMachineDemoTests/<TestClass>/<testMethod>
```

For a quick UI-only launch, add `MOCK_LLM` to the target’s Swift Active Compilation Conditions. For real inference, leave `MOCK_LLM` unset, install a valid GGUF in the simulator app container, and use **Load Model**. The app expects `Documents/Models`; if no `.gguf` is present it attempts the configured ModelScope download. The llama.cpp XCFramework is referenced from the local build output path in the project file, so a new checkout must update that path or build the framework first.

## Architecture

The app is a SwiftUI local-chat demo. `ChatView` renders state owned by the `@MainActor` `ChatViewModel`; the view model depends on `LLMService` rather than native llama.cpp types. `MockLLMService` supplies deterministic streamed fragments, while `LlamaCppService` owns the llama.cpp model, context, vocabulary, sampler, tokenization, decoding, cancellation, and native cleanup.

`ModelStore` is an actor in `Inference/MockStore.swift`. It stores models under the app container’s `Documents/Models` directory, discovers the default ModelScope GGUF, downloads to a temporary file, and only publishes the final path after size and SHA-256 validation. The app loads an existing readable `.gguf` first and otherwise starts the automatic download.

`PromptGuard` performs the deliberately naive preflight filter before inference: it rejects oversized prompts and requests needing current information, external tools, actions, or selected sensitive expertise. The context-window UI is an estimate based on retained message text; llama.cpp itself currently receives the formatted current prompt.

## Repository-specific conventions

- Keep UI lifecycle and published state in `ChatViewModel` on `@MainActor`; do not call native inference synchronously from SwiftUI actions.
- Keep native C API details isolated in `LlamaCppService`. Stream output through `AsyncThrowingStream<String, Error>` and preserve cancellation and partial output.
- Use the Llama 3.2 instruct chat template, concise system instruction, and EOS/EOT stopping when changing prompt generation.
- The configured context is 2,048 tokens. Generation is capped at 256 tokens and reduced dynamically by prompt token usage plus a 32-token safety margin.
- The simulator must use CPU inference (`n_gpu_layers = 0`) because its Metal implementation does not support residency sets. Physical devices may use GPU layers.
- Real inference is the default. Define the Swift compilation condition `MOCK_LLM` to run UI work without model weights.
- Do not commit GGUF weights, credentials, private URLs, or model downloads. Model configuration must retain exact byte-count and SHA-256 validation.
- Preserve the existing `LLMService` boundary when adding another runtime or model source; inject services through the app composition point.
- When diagnosing a load failure, distinguish network/download errors, missing or unreadable files, native model/context creation errors, and unsupported simulator Metal features. Do not bypass TLS or checksum validation.
- When changing generation behavior, test a short factual prompt, a longer prompt near the context limit, cancellation during streaming, and a second turn. Treat the context gauge as an estimate unless tokenization is explicitly shared with the UI.
