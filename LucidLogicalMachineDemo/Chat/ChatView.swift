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
                header
                statusBar
                conversation
                composer
            }
            .background(ChatTheme.bg.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
            .alert("Something went wrong", isPresented: errorPresented) {
                Button("OK") { viewModel.dismissError() }
            } message: {
                Text(viewModel.errorMessage ?? "Unknown error")
            }
        }
        .preferredColorScheme(.dark)
        .tint(ChatTheme.accent)
        .onDisappear { viewModel.cancel() }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 11)
                .fill(ChatTheme.surface2)
                .overlay(RoundedRectangle(cornerRadius: 11).strokeBorder(ChatTheme.border))
                .frame(width: 38, height: 38)
                .overlay {
                    Image(systemName: "cpu")
                        .foregroundStyle(ChatTheme.accent)
                }

            VStack(alignment: .leading, spacing: 2) {
                Text("Local LLM")
                    .font(ChatTheme.title(18))
                    .foregroundStyle(ChatTheme.text)
                Label("Runs fully on-device", systemImage: "lock.fill")
                    .font(.system(size: 11.5))
                    .foregroundStyle(ChatTheme.textTertiary)
            }

            Spacer()

            Button(action: viewModel.clear) {
                Image(systemName: "trash")
                    .foregroundStyle(ChatTheme.textSecondary)
                    .frame(width: 38, height: 38)
                    .background(ChatTheme.surface2, in: RoundedRectangle(cornerRadius: 11))
                    .overlay(RoundedRectangle(cornerRadius: 11).strokeBorder(ChatTheme.border))
            }
            .disabled(viewModel.messages.isEmpty && viewModel.state != .generating)
        }
        .padding(.horizontal, 20)
        .padding(.top, 16)
        .padding(.bottom, 4)
    }

    // MARK: - Status card

    private var statusDotColor: Color {
        switch viewModel.state {
        case .ready, .generating: ChatTheme.accent
        case .failed: ChatTheme.danger
        case .notLoaded, .loading: ChatTheme.textTertiary
        }
    }

    private var modelDisplayName: String {
        modelURL.deletingPathExtension().lastPathComponent
    }

    private var statusBar: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                HStack(spacing: 8) {
                    Circle()
                        .fill(statusDotColor)
                        .frame(width: 7, height: 7)
                    Text(viewModel.state.title)
                        .font(.system(size: 13.5, weight: .semibold))
                        .foregroundStyle(ChatTheme.text)
                }
                Spacer()
                Text(modelDisplayName)
                    .font(ChatTheme.mono(11))
                    .foregroundStyle(ChatTheme.textTertiary)

                if viewModel.state == .ready {
                    Button(action: loadOrDownload) {
                        Image(systemName: "arrow.triangle.2.circlepath")
                            .font(.system(size: 12))
                            .foregroundStyle(ChatTheme.textSecondary)
                            .frame(width: 26, height: 26)
                            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(ChatTheme.border))
                    }
                }
            }

            ContextWindowView(
                usedTokens: viewModel.contextTokensUsed,
                capacity: 2_048,
                tokensPerSecond: viewModel.contextTokensPerSecond
            )

            if viewModel.state == .notLoaded {
                Text("Load the local model before sending a prompt.")
                    .font(.caption)
                    .foregroundStyle(ChatTheme.textTertiary)
            }

            if viewModel.state != .ready {
                HStack(spacing: 12) {
                    Button("Load Model", systemImage: "arrow.down.circle", action: loadOrDownload)
                        .buttonStyle(.borderedProminent)
                        .tint(ChatTheme.accent)
                        .foregroundStyle(ChatTheme.accentOn)
                        .disabled(viewModel.state == .loading || viewModel.state == .generating)

                    if viewModel.state == .loading {
                        ProgressView(value: viewModel.modelProgress)
                            .tint(ChatTheme.accent)
                    } else if viewModel.state == .generating {
                        Button("Cancel", systemImage: "stop.circle", action: viewModel.cancel)
                            .buttonStyle(.bordered)
                    }
                }
            }
        }
        .padding(16)
        .background(ChatTheme.surface, in: RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(ChatTheme.border))
        .padding(.horizontal, 20)
        .padding(.top, 4)
        .padding(.bottom, 14)
    }

    private func loadOrDownload() {
        Task {
            if FileManager.default.isReadableFile(atPath: modelURL.path) {
                await viewModel.load(modelURL: modelURL)
            } else {
                await viewModel.downloadAndLoadDefaultModel()
            }
        }
    }

    // MARK: - Conversation

    private var conversation: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 14) {
                    if viewModel.messages.isEmpty {
                        ContentUnavailableView("Start a conversation",
                                               systemImage: "bubble.left.and.bubble.right",
                                               description: Text("Ask the local model a question."))
                            .foregroundStyle(ChatTheme.textSecondary)
                            .frame(maxWidth: .infinity)
                            .padding(.top, 60)
                    }
                    ForEach(viewModel.messages) { message in
                        messageBubble(message).id(message.id)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 4)
            }
            .onChange(of: viewModel.messages.count) {
                if let last = viewModel.messages.last {
                    withAnimation { proxy.scrollTo(last.id) }
                }
            }
        }
    }

    // MARK: - Composer

    private var composer: some View {
        HStack(alignment: .center, spacing: 10) {
            TextField("Ask the local model...", text: $prompt, axis: .vertical)
                .font(.system(size: 15))
                .foregroundStyle(ChatTheme.text)
                .lineLimit(1...5)
                .padding(.horizontal, 16)
                .padding(.vertical, 11)
                .background(ChatTheme.surface2, in: Capsule())
                .overlay(Capsule().strokeBorder(ChatTheme.border))
                .disabled(viewModel.state != .ready)

            Button(action: send) {
                Image(systemName: "paperplane.fill")
                    .font(.system(size: 16))
                    .foregroundStyle(ChatTheme.accentOn)
                    .frame(width: 44, height: 44)
                    .background(sendEnabled ? ChatTheme.accent : ChatTheme.surface2, in: Circle())
                    .shadow(color: sendEnabled ? ChatTheme.accentBgStrong : .clear, radius: 10)
            }
            .disabled(!sendEnabled)
            .accessibilityLabel("Send prompt")
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 20)
        .background(
            ChatTheme.surface
                .overlay(Rectangle().frame(height: 1).foregroundStyle(ChatTheme.border), alignment: .top)
                .ignoresSafeArea(edges: .bottom)
        )
    }

    private var sendEnabled: Bool {
        viewModel.state == .ready && !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func send() {
        let text = prompt
        prompt = ""
        viewModel.send(prompt: text)
    }

    // MARK: - Bubbles

    @ViewBuilder
    private func messageBubble(_ message: ChatMessage) -> some View {
        HStack(alignment: .top, spacing: 8) {
            if message.role == .assistant {
                avatar
                if message.text.isEmpty && viewModel.state == .generating {
                    TypingIndicatorView()
                        .padding(13)
                        .background(ChatTheme.surface, in: assistantShape)
                        .overlay(assistantShape.strokeBorder(ChatTheme.border))
                } else {
                    bubble(message.text, shape: assistantShape, fill: ChatTheme.surface, border: ChatTheme.border)
                }
                Spacer(minLength: 36)
            } else {
                Spacer(minLength: 36)
                bubble(message.text, shape: userShape, fill: ChatTheme.accentBg, border: ChatTheme.accentBgStrong)
            }
        }
    }

    private var avatar: some View {
        Image(systemName: "bolt.fill")
            .font(.system(size: 11))
            .foregroundStyle(ChatTheme.accent)
            .frame(width: 24, height: 24)
            .background(ChatTheme.surface2, in: RoundedRectangle(cornerRadius: 7))
            .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(ChatTheme.border))
            .padding(.top, 2)
    }

    private var assistantShape: UnevenRoundedRectangle {
        UnevenRoundedRectangle(topLeadingRadius: 18, bottomLeadingRadius: 4, bottomTrailingRadius: 18, topTrailingRadius: 18)
    }

    private var userShape: UnevenRoundedRectangle {
        UnevenRoundedRectangle(topLeadingRadius: 18, bottomLeadingRadius: 18, bottomTrailingRadius: 4, topTrailingRadius: 18)
    }

    private func bubble(_ text: String, shape: UnevenRoundedRectangle, fill: Color, border: Color) -> some View {
        Text(text)
            .font(.system(size: 15))
            .foregroundStyle(ChatTheme.text)
            .textSelection(.enabled)
            .padding(12)
            .background(fill, in: shape)
            .overlay(shape.strokeBorder(border))
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
        fill >= 0.9 ? ChatTheme.danger : fill >= 0.7 ? .orange : ChatTheme.accent
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text("CONTEXT WINDOW")
                    .font(.system(size: 11.5, weight: .semibold))
                    .tracking(0.4)
                    .foregroundStyle(ChatTheme.textSecondary)
                Spacer()
                Text("\(usedTokens) / \(capacity) tok" + (tokensPerSecond > 0 ? String(format: " · %.1f tok/s", tokensPerSecond) : ""))
                    .font(ChatTheme.mono(11.5))
                    .foregroundStyle(ChatTheme.textTertiary)
            }
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule().fill(ChatTheme.surface2)
                    Capsule()
                        .fill(color)
                        .frame(width: geometry.size.width * fill)
                        .animation(.linear(duration: 0.15), value: fill)
                }
            }
            .frame(height: 6)
        }
    }
}

private struct TypingIndicatorView: View {
    @State private var animate = false

    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<3, id: \.self) { i in
                Circle()
                    .fill(ChatTheme.textTertiary)
                    .frame(width: 6, height: 6)
                    .offset(y: animate ? -4 : 0)
                    .animation(
                        .easeInOut(duration: 0.6).repeatForever(autoreverses: true).delay(Double(i) * 0.15),
                        value: animate
                    )
            }
        }
        .onAppear { animate = true }
    }
}
