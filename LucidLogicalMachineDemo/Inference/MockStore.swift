//
//  MockStore.swift
//  LucidLogicalMachineDemo
//
//  Created by A422GQ on 25/08/2026.
//

import CryptoKit
import Foundation

actor ModelStore{
    private static let defaultRepository = "bartowski/FuseChat-Llama-3.2-1B-Instruct-GGUF"
    private static let defaultFilename = "FuseChat-Llama-3.2-1B-Instruct-Q4_K_M.gguf"
    private static let defaultSHA256 = "8bcd46580c2eb069fde82b4c16f8f2981901d653fea1340ec560b6097f08f97a"

    struct Configuration: Sendable {
        let filename: String
        let remoteURL: URL
        let expectedBytes: Int64
        let sha256: String
    }
    
    enum StoreError: LocalizedError {
        case invalidConfiguration
        case invalidRemoteResponse
        case sizeMismatch(expected: Int64, actual: Int64)
        case checksumMismatch
        case missingModel
        
        var errorDescription: String? {
            switch self {
            case .invalidConfiguration:
                return "Invalid model store configuration"
            case .invalidRemoteResponse:
                return "Invalid response from remote"
            case .sizeMismatch(expected: let expected, actual: let actual):
                return "Expected \(expected) bytes, but got \(actual)"
            case .checksumMismatch:
                return "Checksum mismatch"
            case .missingModel:
                return "Model not found"
            }
        }
    }
        
    private let configuration: Configuration
    private let fileManager = FileManager.default
        
    init(configuration: Configuration) {
        self.configuration = configuration
    }

    static func discoverDefault() async throws -> ModelStore {
        let remoteURL = URL(string: "https://modelscope.cn/models/\(defaultRepository)/resolve/master/\(defaultFilename)")!
        var request = URLRequest(url: remoteURL)
        request.setValue("bytes=0-0", forHTTPHeaderField: "Range")
        let (_, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw StoreError.invalidRemoteResponse
        }
        let size = http.value(forHTTPHeaderField: "Content-Range")
            .flatMap { Int64($0.split(separator: "/").last ?? "") }
            ?? response.expectedContentLength
        guard size > 0 else {
            throw StoreError.invalidRemoteResponse
        }
        return ModelStore(configuration: .init(
            filename: defaultFilename,
            remoteURL: remoteURL,
            expectedBytes: size,
            sha256: defaultSHA256
        ))
    }
        
    private var modelsDirectory: URL {
        fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("Models", isDirectory: true)
    }
    
    private var modelURL: URL {
        modelsDirectory.appendingPathComponent(configuration.filename)
    }
    
    func existingModelURL() -> URL? {
        guard fileManager.fileExists(atPath: modelURL.path),
              (try? modelURL.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true else {
            return nil
        }
        guard let attributes = try? fileManager.attributesOfItem(atPath: modelURL.path),
              let size = attributes[.size] as? NSNumber,
              size.int64Value == configuration.expectedBytes,
              let data = try? Data(contentsOf: modelURL) else {
            return nil
        }
        let digest = SHA256.hash(data: data)
            .map { String(format: "%02x", $0) }
            .joined()
        guard digest.caseInsensitiveCompare(configuration.sha256) == .orderedSame else {
            return nil
        }
        return modelURL
    }
    
    func download(progress: @escaping @Sendable (Double) -> Void) async throws -> URL {
        let filenameURL = URL(fileURLWithPath: configuration.filename)
        guard !configuration.filename.isEmpty,
              filenameURL.lastPathComponent == configuration.filename,
              configuration.expectedBytes > 0,
              ["http", "https"].contains(configuration.remoteURL.scheme?.lowercased()),
              configuration.sha256.count == SHA256.Digest.byteCount * 2,
              configuration.sha256.allSatisfy(\.isHexDigit) else {
            throw StoreError.invalidConfiguration
        }
        try fileManager.createDirectory(at: modelsDirectory, withIntermediateDirectories: true)
        
        let temporaryURL = modelsDirectory.appendingPathComponent(configuration.filename + ".download")
        
        try? fileManager.removeItem(at: temporaryURL)
        guard fileManager.createFile(atPath: temporaryURL.path, contents: nil) else {
            throw StoreError.invalidConfiguration
        }
        
        do {
            
            let (bytes, response) = try await URLSession.shared.bytes(from: configuration.remoteURL)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                throw StoreError.invalidRemoteResponse
            }
            
            let contentLength = response.expectedContentLength > 0 ? response.expectedContentLength : configuration.expectedBytes
            var received: Int64 = 0
            var hasher = SHA256()
            var buffer = Data()
            
            let handle = try FileHandle(forWritingTo: temporaryURL)
            defer { try? handle.close() }
            
            for try await byte in bytes {
                try Task.checkCancellation()
                buffer.append(byte)
                if buffer.count >= 64 * 1024 {
                    try handle.write(contentsOf: buffer)
                    hasher.update(data: buffer)
                    received += Int64(buffer.count)
                    buffer.removeAll(keepingCapacity: true)
                    progress(min(Double(received) / Double(max(contentLength, 1)), 1.0))
                }
            }
            
            if !buffer.isEmpty {
                try handle.write(contentsOf: buffer)
                hasher.update(data: buffer)
                received += Int64(buffer.count)
                progress(min(Double(received) / Double(max(contentLength, 1)), 1.0))
            }
            
            guard received == configuration.expectedBytes else {
                throw StoreError.sizeMismatch(expected: configuration.expectedBytes, actual: received)
            }
            
            let actualHash = hasher.finalize().map { String(format: "%02x", $0) }.joined()
            
            guard actualHash.caseInsensitiveCompare(configuration.sha256) == .orderedSame else {
                throw StoreError.checksumMismatch
            }
            
            try handle.synchronize()
            try handle.close()
            try? fileManager.removeItem(at: modelURL)
            try fileManager.moveItem(at: temporaryURL, to: modelURL)
            progress(1.0)
            return modelURL
        } catch {
            try? fileManager.removeItem(at: temporaryURL)
            throw error
        }
    }
}
