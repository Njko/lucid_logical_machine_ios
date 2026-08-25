//
//  MockLLMService.swift
//  LucidLogicalMachineDemo
//
//  Created by A422GQ on 25/08/2026.
//

import Foundation

final class MockLLMService: LLMService, @unchecked Sendable {
    func load(modelURL: URL) async throws {
        // Mock mode deliberately does not require a model file.
    }

    func stream(prompt: String) -> AsyncThrowingStream<String, Error> {
        return AsyncThrowingStream { continuation in
            let response = "Mock response to: \(prompt)"
            for word in response.split(separator: " ", omittingEmptySubsequences: false) {
                guard !Task.isCancelled else {
                    continuation.finish()
                    return
                }
                continuation.yield(String(word) + " ")
            }
            continuation.finish()
        }
    }

    func unload() async {
    }
}
