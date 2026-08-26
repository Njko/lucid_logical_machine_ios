# Agent instructions

## Before editing

- Read `.github/copilot-instructions.md` and this file.
- Inspect `git status`; preserve unrelated user changes.
- Do not add GGUF weights, credentials, or private URLs.

## Project shape

- `Chat/ChatView.swift` renders the SwiftUI interface.
- `Chat/ChatViewModel.swift` owns main-actor state and task cancellation.
- `Inference/LLMService.swift` is the runtime boundary.
- `Inference/LlamaCppService.swift` contains all llama.cpp C API calls.
- `Inference/MockStore.swift` contains the actor-backed `ModelStore`.
- `Inference/PromptGuard.swift` contains naive prompt admission rules.

Keep these boundaries intact. SwiftUI actions must start asynchronous work; native model work must not run synchronously on the main actor.

## Validation

Run the simulator build:

```bash
xcodebuild -project LucidLogicalMachineDemo.xcodeproj \
  -scheme LucidLogicalMachineDemo \
  -sdk iphonesimulator \
  -configuration Debug \
  build CODE_SIGNING_ALLOWED=NO
```

There is currently no XCTest target or lint configuration. Use `MOCK_LLM` for fast UI validation without downloading a model. For real inference, use a valid `.gguf` in `Documents/Models` and keep checksum validation enabled.

On the simulator, keep `n_gpu_layers = 0`; physical devices may enable GPU layers. Preserve the Llama 3.2 chat template, EOS/EOT stopping, the 4,096-token context, and the dynamic 256-token output budget unless the behavior is intentionally being changed.
