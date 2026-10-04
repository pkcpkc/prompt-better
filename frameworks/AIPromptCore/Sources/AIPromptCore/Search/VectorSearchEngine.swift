import Foundation
import NaturalLanguage
import Accelerate

/// Local in-memory semantic vector search engine using NLEmbedding and Accelerate vDSP.
public actor VectorSearchEngine {
    public static let shared = VectorSearchEngine()

    public struct VectorRecord: Sendable {
        public let id: String
        public let title: String
        public let content: String
        public let metadata: [String: String]?
        public let vector: [Float] // L2-normalized float vector
    }

    private var records: [String: VectorRecord] = [:]

    public init() {}

    /// Adds or updates a document in the vector index.
    public func add(id: String, title: String, content: String, metadata: [String: String]? = nil) {
        guard let vector = computeEmbedding(for: "\(title)\n\(content)") else { return }
        records[id] = VectorRecord(
            id: id,
            title: title,
            content: content,
            metadata: metadata,
            vector: vector
        )
    }

    /// Deletes a document by ID.
    public func delete(id: String) {
        records.removeValue(forKey: id)
    }

    /// Clears all vector records.
    public func clear() {
        records.removeAll()
    }

    /// Returns the number of indexed records.
    public var count: Int {
        records.count
    }

    /// Performs semantic cosine similarity search.
    public func search(query: String, limit: Int = 5, minScore: Double? = nil) -> [OpenAI.SearchResult] {
        guard let queryVector = computeEmbedding(for: query) else { return [] }
        let threshold = Float(minScore ?? 0.0)

        var scored: [(score: Float, record: VectorRecord)] = []
        let dim = vDSP_Length(queryVector.count)

        for record in records.values {
            guard record.vector.count == queryVector.count else { continue }
            var dotProduct: Float = 0
            vDSP_dotpr(queryVector, 1, record.vector, 1, &dotProduct, dim)

            if dotProduct >= threshold {
                scored.append((score: dotProduct, record: record))
            }
        }

        return scored
            .sorted { $0.score > $1.score }
            .prefix(limit)
            .map { item in
                OpenAI.SearchResult(
                    id: item.record.id,
                    score: Double(item.score),
                    title: item.record.title,
                    content: item.record.content,
                    metadata: item.record.metadata
                )
            }
    }

    // MARK: - Embedding & Normalization Helpers

    public func computeEmbedding(for text: String) -> [Float]? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        guard let embedding = NLEmbedding.sentenceEmbedding(for: .english) else {
            return nil
        }

        // For shorter texts (< 250 characters), single sentence vector is optimal
        if trimmed.count < 250, let vec = embedding.vector(for: trimmed) {
            return normalize(vec.map { Float($0) })
        }

        // For longer paragraphs, tokenize sentences and perform L2-normalized mean pooling
        let tokenizer = NLTokenizer(unit: .sentence)
        tokenizer.string = trimmed

        var vectors: [[Float]] = []
        tokenizer.enumerateTokens(in: trimmed.startIndex..<trimmed.endIndex) { range, _ in
            let sentence = String(trimmed[range]).trimmingCharacters(in: .whitespacesAndNewlines)
            if !sentence.isEmpty, let v = embedding.vector(for: sentence) {
                vectors.append(v.map { Float($0) })
            }
            return true
        }

        guard !vectors.isEmpty else {
            return embedding.vector(for: trimmed).map { normalize($0.map { Float($0) }) }
        }

        let dim = vectors[0].count
        var mean = [Float](repeating: 0, count: dim)
        for v in vectors {
            for i in 0..<dim {
                mean[i] += v[i]
            }
        }
        let count = Float(vectors.count)
        for i in 0..<dim {
            mean[i] /= count
        }

        return normalize(mean)
    }

    private func normalize(_ vector: [Float]) -> [Float] {
        guard !vector.isEmpty else { return vector }
        var norm: Float = 0
        vDSP_svesq(vector, 1, &norm, vDSP_Length(vector.count))
        let length = sqrt(norm)
        guard length > 0.00001 else { return vector }

        var normalized = [Float](repeating: 0, count: vector.count)
        var divisor = length
        vDSP_vsdiv(vector, 1, &divisor, &normalized, 1, vDSP_Length(vector.count))
        return normalized
    }
}
