# iOS Local LLM Demo Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implement the local llama.cpp SwiftUI chat demo described in the tutorial, with a complete mock path and isolated real-service adapter.

**Architecture:** Keep UI state in `ChatViewModel` and native inference behind `LLMService`. `ModelStore` owns model location and integrity validation; `MockLLMService` enables deterministic development without weights; `LlamaCppService` isolates the revision-specific XCFramework API.

**Tech Stack:** SwiftUI, Swift concurrency actors/AsyncThrowingStream, Foundation URLSession, CryptoKit, XCTest, llama.cpp XCFramework.

---

## Chunk 1: Inference and lifecycle

### Task 1: Complete shared models and mock service

**Files:**
- Modify: `LucidLogicalMachineDemo/Chat/ChatMessage.swift`
- Modify: `LucidLogicalMachineDemo/Inference/MockLLMService.swift`

- [ ] Add a stable role representation suitable for SwiftUI rendering and test equality.
- [ ] Implement deterministic word-fragment streaming and cancellation checks.
- [ ] Keep `load` and `unload` no-ops for mock mode.
- [ ] Compile the app target.

### Task 2: Implement model storage

**Files:**
- Modify: `LucidLogicalMachineDemo/Inference/MockStore.swift`

- [ ] Preserve the actor boundary and Documents/Models location.
- [ ] Download into a `.download` temporary file.
- [ ] Validate HTTP status, exact byte count, and SHA-256 before moving to the final path.
- [ ] Remove temporary files on every error or cancellation.
- [ ] Compile the app target.

### Task 3: Implement the real llama.cpp adapter

**Files:**
- Modify: `LucidLogicalMachineDemo/Inference/LlamaCppService.swift`

- [ ] Keep model/context handles actor-isolated.
- [ ] Load and unload in context-before-model order.
- [ ] Expose streamed fragments through `AsyncThrowingStream`.
- [ ] Keep framework-specific calls localized and provide a clear unavailable/error path if the checked-out wrapper API differs.
- [ ] Compile against the referenced XCFramework and fix only adapter-specific API issues.

### Task 4: Build the main-actor view model

**Files:**
- Modify: `LucidLogicalMachineDemo/Chat/ChatViewModel.swift`

- [ ] Add explicit notLoaded/loading/ready/generating/failed state.
- [ ] Implement load, send, cancel, and clear task lifecycle.
- [ ] Ignore blank prompts and block concurrent sends.
- [ ] Preserve partial assistant output and useful failure text.
- [ ] Add focused XCTest coverage for each lifecycle behavior.

## Chunk 2: SwiftUI surface and app wiring

### Task 5: Build the chat screen

**Files:**
- Modify: `LucidLogicalMachineDemo/Chat/ChatView.swift`

- [ ] Render user and assistant bubbles in a scrollable conversation.
- [ ] Add multiline input, Send, Cancel, Load Model, Clear, progress, state, and error UI.
- [ ] Disable actions according to view-model state while keeping mock mode usable.

### Task 6: Wire app dependencies

**Files:**
- Modify: `LucidLogicalMachineDemo/App/LucidLogicalMachineDemoApp.swift`
- Modify: `LucidLogicalMachineDemo.xcodeproj/project.pbxproj` only if target membership or framework settings require it.

- [ ] Construct a non-secret model configuration.
- [ ] Default to `MockLLMService` for reliable UI launch, with a single switchable service composition point.
- [ ] Ensure all source files are included and the XCFramework remains linked/embedded.

## Chunk 3: Validation

### Task 7: Run focused and target validation

**Files:**
- Test: `LucidLogicalMachineDemoTests/ChatViewModelTests.swift`

- [ ] Run the focused view-model tests on an installed iOS Simulator.
- [ ] Run the complete test target.
- [ ] Build the app target and confirm no model weights or secrets are tracked.

