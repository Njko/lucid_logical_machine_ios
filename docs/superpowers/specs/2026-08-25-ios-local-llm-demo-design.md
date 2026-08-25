# iOS Local LLM Demo Design

**Goal:** Deliver a SwiftUI chat demo that runs in mock mode immediately and can load/stream a local GGUF model through the already referenced llama.cpp XCFramework.

**Architecture:** `ChatView` depends on a `@MainActor` `ChatViewModel`, which depends only on the `LLMService` protocol and an actor-isolated `ModelStore`. `MockLLMService` provides deterministic UI behavior; `LlamaCppService` keeps native llama.cpp handles and API details isolated behind the same protocol.

**Scope:** Implement the chat model, loading/generation lifecycle, model-file validation, mock streaming, SwiftUI controls, and app wiring. Preserve the existing user worktree changes and do not add model weights or credentials. The native service must compile against the referenced framework when its Swift API is available; if the checked-in framework exposes a revision-specific wrapper, only `LlamaCppService` should require adaptation.

**Data flow:** Load resolves an existing validated model or downloads to a temporary file, verifies byte count and SHA-256, then atomically moves it into `Documents/Models`. Send appends user and assistant messages, consumes streamed fragments, and preserves partial output on cancellation or failure. Clear cancels generation and removes messages without unloading a ready model.

**Error handling:** Invalid HTTP responses, size mismatches, checksum failures, missing files, native load failures, and generation failures become explicit state or localized errors. Cancellation is treated as a lifecycle event and never publishes a completed response.

**Testing:** Add focused unit tests around `ChatViewModel` with a controllable mock service for blank input, loading, ordered streaming, cancellation, failure, duplicate sends, and clear behavior. Validate the app target with the available Xcode simulator destination.
