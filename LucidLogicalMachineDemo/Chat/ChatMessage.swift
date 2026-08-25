//
//  ChatMessage.swift
//  LucidLogicalMachineDemo
//
//  Created by A422GQ on 25/08/2026.
//

import Foundation

struct ChatMessage: Identifiable, Equatable {
    enum Role: String, Codable, Sendable {
        case user
        case assistant
    }
    
    let id: UUID
    let role: Role
    var text: String

    init(id: UUID = UUID(), role: Role, text: String) {
        self.id = id
        self.role = role
        self.text = text
    }
}
