import SwiftUI

struct ChatView: View {
    @StateObject private var viewModel: ChatViewModel
    let modelURL: URL
    @State private var prompt = ""

    init(service: any LLMService, modelURL: URL) {
        _viewModel = StateObject(wrappedValue: ChatViewModel(service: service))
        self.modelURL = modelURL
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                statusBar
                conversation
                composer
            }
            .navigationTitle("Local LLM")
            .toolbar {
                ToolbarItem(placement: .automatic) {
                    Button("Clear", systemImage: "trash", action: viewModel.clear)
                        .disabled(viewModel.messages.isEmpty && viewModel.state != .generating)
                }
            }
            .alert("Something went wrong", isPresented: errorPresented) {
                Button("OK") { viewModel.dismissError() }
            } message: {
                Text(viewModel.errorMessage ?? "Unknown error")
            }
        }
        .onDisappear { viewModel.cancel() }
    }

    private var statusBar: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label(viewModel.state.title, systemImage: viewModel.state == .ready ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(viewModel.state == .ready ? .green : .secondary)
                Spacer()
                if viewModel.state == .loading { ProgressView() }
            }
            if viewModel.state == .notLoaded {
                Text("Load the local model before sending a prompt.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            ContextWindowView(
                usedTokens: viewModel.contextTokensUsed,
                capacity: 2_048,
                tokensPerSecond: viewModel.contextTokensPerSecond
            )
            HStack(spacing: 12) {
                Button("Load Model", systemImage: "arrow.down.circle") {
                    Task {
                        if FileManager.default.isReadableFile(atPath: modelURL.path) {
                            await viewModel.load(modelURL: modelURL)
                        } else {
                            await viewModel.downloadAndLoadDefaultModel()
                        }
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(viewModel.state == .loading || viewModel.state == .generating)

                if viewModel.state == .loading {
                    ProgressView(value: viewModel.modelProgress)
                } else if viewModel.state == .generating {
                    Button("Cancel", systemImage: "stop.circle", action: viewModel.cancel)
                        .buttonStyle(.bordered)
                }
            }
        }
        .padding()
        .background(.thinMaterial)
    }

    private var conversation: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    if viewModel.messages.isEmpty {
                        ContentUnavailableView("Start a conversation",
                                               systemImage: "bubble.left.and.bubble.right",
                                               description: Text("Ask the local model a question."))
                            .frame(maxWidth: .infinity)
                            .padding(.top, 60)
                    }
                    ForEach(viewModel.messages) { message in
                        messageBubble(message).id(message.id)
                    }
                }
                .padding()
            }
            .onChange(of: viewModel.messages.count) {
                if let last = viewModel.messages.last {
                    withAnimation { proxy.scrollTo(last.id) }
                }
            }
        }
    }

    private var composer: some View {
        HStack(alignment: .bottom, spacing: 10) {
            TextField("Ask the local model...", text: $prompt, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(1...5)
                .disabled(viewModel.state != .ready)
            Button("Send", systemImage: "paperplane.fill") {
                let text = prompt
                prompt = ""
                viewModel.send(prompt: text)
            }
            .labelStyle(.iconOnly)
            .buttonStyle(.borderedProminent)
            .disabled(viewModel.state != .ready || prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .accessibilityLabel("Send prompt")
        }
        .padding()
        .background(.bar)
    }

    @ViewBuilder
    private func messageBubble(_ message: ChatMessage) -> some View {
        HStack {
            if message.role == .assistant {
                bubble(message.text, color: .secondary.opacity(0.15))
                Spacer(minLength: 36)
            } else {
                Spacer(minLength: 36)
                bubble(message.text, color: .accentColor.opacity(0.2))
            }
        }
    }

    private func bubble(_ text: String, color: Color) -> some View {
        Text(text)
            .textSelection(.enabled)
            .padding(12)
            .background(color, in: RoundedRectangle(cornerRadius: 16))
    }

    private var errorPresented: Binding<Bool> {
        Binding(get: { viewModel.errorMessage != nil },
                set: { if !$0 { viewModel.dismissError() } })
    }
}

private struct ContextWindowView: View {
    let usedTokens: Int
    let capacity: Int
    let tokensPerSecond: Double

    private var fill: Double {
        min(Double(usedTokens) / Double(capacity), 1)
    }

    private var color: Color {
        fill >= 0.9 ? .red : fill >= 0.7 ? .orange : .accentColor
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Context window")
                    .font(.caption.weight(.semibold))
                Spacer()
                Text("\(usedTokens) / \(capacity) tokens")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule().fill(.secondary.opacity(0.15))
                    Capsule()
                        .fill(color)
                        .frame(width: geometry.size.width * fill)
                        .animation(.linear(duration: 0.15), value: fill)
                }
            }
            .frame(height: 7)
            if tokensPerSecond > 0 {
                Text(String(format: "+%.1f tokens/s", tokensPerSecond))
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
    }
}
