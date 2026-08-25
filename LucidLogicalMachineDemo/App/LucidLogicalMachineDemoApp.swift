//
//  LucidLogicalMachineDemoApp.swift
//  LucidLogicalMachineDemo
//
//  Created by A422GQ on 25/08/2026.
//

import SwiftUI
import Foundation

@main
struct LucidLogicalMachineDemoApp: App {
    private let dependencies = Dependencies()

    var body: some Scene {
        WindowGroup {
            ChatView(service: dependencies.service, modelURL: dependencies.modelURL)
        }
    }
}

/// Central composition point. Define MOCK_LLM in build settings when developing
/// the UI without model weights.
private struct Dependencies {
    let service: any LLMService
    let modelURL: URL

    init() {
        #if MOCK_LLM
        service = MockLLMService()
        #else
        service = LlamaCppService()
        #endif
        let modelsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Models", isDirectory: true)
        let defaultURL = modelsDirectory.appendingPathComponent("model.gguf")
        modelURL = (try? FileManager.default.contentsOfDirectory(
            at: modelsDirectory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ))?.first(where: { $0.pathExtension.lowercased() == "gguf" }) ?? defaultURL
    }
}
