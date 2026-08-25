//
//  LLMService.swift
//  LucidLogicalMachineDemo
//
//  Created by A422GQ on 25/08/2026.
//

import Foundation

protocol LLMService: Sendable {
    func load(modelURL: URL) async throws
    func stream(prompt: String) -> AsyncThrowingStream<String, Error>
    func unload() async
}
