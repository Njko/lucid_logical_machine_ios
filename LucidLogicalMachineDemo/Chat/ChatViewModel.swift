import Combine
import Foundation

@MainActor
final class ChatViewModel: ObservableObject {
    enum State: Equatable {
        case notLoaded
        case loading
        case ready
        case generating
        case failed(String)

        var title: String {
            switch self {
            case .notLoaded: "Model not loaded"
            case .loading: "Loading model..."
            case .ready: "Ready"
            case .generating: "Generating..."
            case .failed: "Error"
            }
        }
    }

    @Published private(set) var state: State = .notLoaded
    @Published private(set) var messages: [ChatMessage] = []
    @Published private(set) var modelProgress = 0.0
    @Published private(set) var contextTokensUsed = 0
    @Published private(set) var contextTokensPerSecond = 0.0

    var errorMessage: String? {
        guard case let .failed(message) = state else { return nil }
        return message
    }

    private let service: any LLMService
    private let promptGuard = PromptGuard()
    private var loadTask: Task<Void, Never>?
    private var generationTask: Task<Void, Never>?
    private var generationID: UUID?
    private var modelLoaded = false
    private let contextCapacity = 4_096
    private var generationStartedAt: Date?
    private var generationStartTokens = 0

    init(service: any LLMService) {
        self.service = service
    }

    deinit {
        loadTask?.cancel()
        generationTask?.cancel()
    }

    func load(modelURL: URL) async {
        guard loadTask == nil, generationTask == nil else { return }
        modelLoaded = false
        state = .loading
        let task = Task { @MainActor [service] in
            defer { loadTask = nil }
            do {
                try await service.load(modelURL: modelURL)
                guard !Task.isCancelled else {
                    state = .notLoaded
                    return
                }
                modelLoaded = true
                state = .ready
            } catch is CancellationError {
                if state == .loading { state = .notLoaded }
            } catch {
                state = .failed(error.localizedDescription)
            }
        }
        loadTask = task
        await task.value
    }

    func downloadAndLoadDefaultModel() async {
        guard loadTask == nil, generationTask == nil else { return }
        state = .loading
        modelProgress = 0
        let task = Task { @MainActor [service] in
            defer { loadTask = nil }
            do {
                let store = try await ModelStore.discoverDefault()
                let url = try await store.download { [weak self] progress in
                    Task { @MainActor in self?.modelProgress = progress }
                }
                try await service.load(modelURL: url)
                guard !Task.isCancelled else {
                    state = .notLoaded
                    return
                }
                modelLoaded = true
                state = .ready
            } catch is CancellationError {
                if state == .loading { state = .notLoaded }
            } catch {
                state = .failed(error.localizedDescription)
            }
        }
        loadTask = task
        await task.value
    }

    func send(prompt: String) {
        let prompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty, state == .ready, generationTask == nil else { return }

        messages.append(ChatMessage(role: .user, text: prompt))
        if case let .rejected(reason) = promptGuard.evaluate(prompt) {
            messages.append(ChatMessage(role: .assistant, text: reason))
            return
        }
        messages.append(ChatMessage(role: .assistant, text: ""))
        updateContextUsage()
        generationStartedAt = Date()
        generationStartTokens = contextTokensUsed
        let assistantIndex = messages.index(before: messages.endIndex)
        let id = UUID()
        generationID = id
        state = .generating

        let task = Task { [service] in
            do {
                for try await fragment in service.stream(prompt: prompt) {
                    guard generationID == id else { return }
                    messages[assistantIndex].text += fragment
                    updateContextUsage()
                    if let startedAt = generationStartedAt {
                        let elapsed = max(Date().timeIntervalSince(startedAt), 0.001)
                        contextTokensPerSecond = Double(contextTokensUsed - generationStartTokens) / elapsed
                    }
                }
                guard generationID == id, !Task.isCancelled else { return }
                state = .ready
            } catch is CancellationError {
                guard generationID == id else { return }
                state = .ready
            } catch {
                guard generationID == id else { return }
                state = .failed(error.localizedDescription)
            }
            if generationID == id {
                generationTask = nil
                generationID = nil
            }
        }
        generationTask = task
    }

    func cancel() {
        if state == .loading {
            loadTask?.cancel()
        } else if state == .generating {
            generationTask?.cancel()
            state = .ready
            generationID = nil
            generationTask = nil
        }
    }

    func clear() {
        generationTask?.cancel()
        generationID = nil
        generationTask = nil
        messages.removeAll()
        contextTokensUsed = 0
        contextTokensPerSecond = 0
        if state == .generating { state = .ready }
    }

    func dismissError() {
        if case .failed = state {
            state = modelLoaded ? .ready : .notLoaded
        }
    }

    private func updateContextUsage() {
        let characters = messages.reduce(0) { $0 + $1.text.utf8.count }
        let messageOverhead = messages.count * 4
        contextTokensUsed = min(contextCapacity, (characters + messageOverhead + 3) / 4)
    }
}
