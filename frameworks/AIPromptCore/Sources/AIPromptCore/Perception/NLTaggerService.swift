import Foundation
import NaturalLanguage

/// In-process linguistic tagging and named-entity recognition using `NLTagger`.
public final class NLTaggerService: @unchecked Sendable {
    public static let shared = NLTaggerService()
    
    public init() {}
    
    public struct Analysis: Codable, Sendable {
        public struct Entity: Codable, Sendable {
            public let text: String
            public let type: String
        }
        public struct Token: Codable, Sendable {
            public let text: String
            public let lexicalClass: String
        }
        public let language: String?
        public let entities: [Entity]
        public let tokens: [Token]
    }
    
    public func analyze(text: String) -> Analysis {
        let language = NLLanguageRecognizer.dominantLanguage(for: text)
        
        let tagger = NLTagger(tagSchemes: [.nameType, .lexicalClass])
        tagger.string = text
        if let language { tagger.setLanguage(language, range: text.startIndex..<text.endIndex) }
        
        let options: NLTagger.Options = [.omitWhitespace, .omitPunctuation, .joinNames]
        var entities: [Analysis.Entity] = []
        var tokens: [Analysis.Token] = []
        
        tagger.enumerateTags(in: text.startIndex..<text.endIndex, unit: .word, scheme: .nameType, options: options) { tag, range in
            if let tag, tag != .otherWord {
                entities.append(.init(text: String(text[range]), type: tag.rawValue))
            }
            return true
        }
        tagger.enumerateTags(in: text.startIndex..<text.endIndex, unit: .word, scheme: .lexicalClass, options: options) { tag, range in
            if let tag {
                tokens.append(.init(text: String(text[range]), lexicalClass: tag.rawValue))
            }
            return true
        }
        
        return Analysis(language: language?.rawValue, entities: entities, tokens: tokens)
    }
    
    /// Returns the analysis encoded as pretty-printed JSON.
    public func analyzeJSON(text: String) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return String(decoding: try encoder.encode(analyze(text: text)), as: UTF8.self)
    }
}
