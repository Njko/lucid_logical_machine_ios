import Foundation

struct PromptGuard: Sendable {
    enum Decision: Equatable, Sendable {
        case allowed
        case rejected(String)
    }

    let maxCharacters: Int
    let maxWords: Int

    init(maxCharacters: Int = 1_200, maxWords: Int = 250) {
        self.maxCharacters = maxCharacters
        self.maxWords = maxWords
    }

    func evaluate(_ prompt: String) -> Decision {
        let normalized = prompt
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .lowercased()
        let words = normalized.split { $0.isWhitespace || $0.isPunctuation }

        if normalized.count > maxCharacters || words.count > maxWords {
            return .rejected("Cette demande est trop longue pour le modele local.")
        }

        let unsupportedPatterns = [
            "actualite", "actualites", "news", "dernier", "derniere",
            "aujourd'hui", "aujourd hui", "en temps reel", "internet",
            "recherche sur le web", "browse", "acheter", "commander",
            "envoyer", "executer", "diagnostic medical", "conseil juridique",
            "investir", "cours de bourse"
        ]
        if unsupportedPatterns.contains(where: normalized.contains) {
            return .rejected("Cette demande necessite des donnees ou des outils que le modele local n'a pas.")
        }

        return .allowed
    }
}
