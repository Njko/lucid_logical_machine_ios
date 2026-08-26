//
//  LlamaCppService.swift
//  LucidLogicalMachineDemo
//
//  Created by A422GQ on 25/08/2026.
//

import Foundation
import llama

final class LlamaCppService: LLMService, @unchecked Sendable {
    private let contextLength = 4_096
    private let maxGeneratedTokens = 256
    private let contextSafetyMargin = 32
    private let systemPrompt = """
    You are a concise and accurate assistant. Answer only the user's question.
    Do not invent exercises, sections, or additional questions. If you are unsure,
    say so. For simple factual questions, use a short list or one or two sentences.
    """

    enum ServiceError: LocalizedError {
        case modelNotLoaded
        case modelFileUnavailable(URL)
        case failedToLoadModel
        case failedToCreateContext
        case tokenizationFailed
        case decodeFailed(Int32)

        var errorDescription: String? {
            switch self {
            case .modelNotLoaded: return "The llama model has not been loaded"
            case .modelFileUnavailable(let url): return "The GGUF file is missing or unreadable: \(url.path)"
            case .failedToLoadModel: return "Unable to load the llama model"
            case .failedToCreateContext: return "Unable to create the llama context"
            case .tokenizationFailed: return "Unable to tokenize the prompt"
            case .decodeFailed(let code): return "Llama decode failed (\(code))"
            }
        }
    }

    private let lock = NSLock()
    private var model: OpaquePointer?
    private var context: OpaquePointer?
    private var sampler: UnsafeMutablePointer<llama_sampler>?
    private var vocab: OpaquePointer?

    init() {
        llama_backend_init()
    }

    deinit {
        unloadSynchronously()
    }

    func load(modelURL: URL) async throws {
        guard modelURL.isFileURL,
              FileManager.default.isReadableFile(atPath: modelURL.path) else {
            throw ServiceError.modelFileUnavailable(modelURL)
        }
        try await Task.detached { [self] in
            lock.lock()
            defer { lock.unlock() }
            freeResources()
            var modelParams = llama_model_default_params()
            #if targetEnvironment(simulator)
            // The iOS Simulator does not provide Metal residency sets.
            modelParams.n_gpu_layers = 0
            #else
            modelParams.n_gpu_layers = -1
            #endif
            guard let loadedModel = modelURL.path.withCString({
                llama_model_load_from_file($0, modelParams)
            }) else {
                throw ServiceError.failedToLoadModel
            }
            var contextParams = llama_context_default_params()
            contextParams.n_ctx = UInt32(contextLength)
            contextParams.n_batch = 512
            guard let loadedContext = llama_init_from_model(loadedModel, contextParams) else {
                llama_model_free(loadedModel)
                throw ServiceError.failedToCreateContext
            }
            guard let loadedVocab = llama_model_get_vocab(loadedModel) else {
                llama_free(loadedContext)
                llama_model_free(loadedModel)
                throw ServiceError.failedToLoadModel
            }
            guard let loadedSampler = llama_sampler_init_greedy() else {
                llama_free(loadedContext)
                llama_model_free(loadedModel)
                throw ServiceError.failedToCreateContext
            }
            model = loadedModel
            context = loadedContext
            vocab = loadedVocab
            sampler = loadedSampler
        }.value
    }

    func stream(prompt: String) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            Task.detached { [self] in
                do {
                    try generate(prompt: prompt, continuation: continuation)
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    func unload() async {
        lock.lock()
        freeResources()
        lock.unlock()
    }

    private func unloadSynchronously() {
        lock.lock()
        freeResources()
        lock.unlock()
    }

    nonisolated private func freeResources() {
        if let sampler { llama_sampler_free(sampler) }
        if let context { llama_free(context) }
        if let model { llama_model_free(model) }
        sampler = nil
        context = nil
        model = nil
        vocab = nil
    }

    nonisolated private func generate(
        prompt: String,
        continuation: AsyncThrowingStream<String, Error>.Continuation
    ) throws {
        lock.lock()
        defer { lock.unlock() }
        guard let context, let vocab, let sampler else {
            throw ServiceError.modelNotLoaded
        }
        let formattedPrompt = """
        <|begin_of_text|><|start_header_id|>system<|end_header_id|>

        \(systemPrompt)<|eot_id|><|start_header_id|>user<|end_header_id|>

        \(prompt)<|eot_id|><|start_header_id|>assistant<|end_header_id|>

        """
        var tokens = Array(repeating: llama_token(0), count: max(256, formattedPrompt.utf8.count + 16))
        let tokenCount = formattedPrompt.withCString {
            llama_tokenize(vocab, $0, Int32(formattedPrompt.utf8.count), &tokens, Int32(tokens.count), true, true)
        }
        guard tokenCount >= 0 else { throw ServiceError.tokenizationFailed }
        tokens.removeSubrange(Int(tokenCount)..<tokens.count)
        var eotTokenBuffer = [llama_token(0)]
        let eotTokenCount = "<|eot_id|>".withCString {
            llama_tokenize(vocab, $0, 9, &eotTokenBuffer, 1, false, true)
        }
        let eotToken = eotTokenCount == 1 ? eotTokenBuffer[0] : nil
        var batch = llama_batch_get_one(&tokens, Int32(tokens.count))
        var result = llama_decode(context, batch)
        guard result >= 0 else { throw ServiceError.decodeFailed(result) }
        let availableTokens = max(1, contextLength - Int(tokenCount) - contextSafetyMargin)
        let generationLimit = min(maxGeneratedTokens, availableTokens)
        for _ in 0..<generationLimit {
            if Task.isCancelled { return }
            let token = llama_sampler_sample(sampler, context, -1)
            if token == llama_vocab_eos(vocab) || token == eotToken { break }
            var buffer = Array(repeating: CChar(0), count: 256)
            let length = llama_token_to_piece(vocab, token, &buffer, Int32(buffer.count), 0, false)
            if length > 0 {
                continuation.yield(String(decoding: buffer.prefix(Int(length)).map { UInt8(bitPattern: $0) }, as: UTF8.self))
            }
            llama_sampler_accept(sampler, token)
            var next = token
            batch = llama_batch_get_one(&next, 1)
            result = llama_decode(context, batch)
            guard result >= 0 else { throw ServiceError.decodeFailed(result) }
        }
    }
}
