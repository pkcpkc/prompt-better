import Foundation
@preconcurrency import NaturalLanguage
import Vision

#if canImport(AppKit)
import AppKit
#endif

#if canImport(UIKit)
import UIKit
#endif

/// In-process actor for generating text and image embeddings.
public actor EmbeddingService {
    public static let shared = EmbeddingService()
    
    private let sentenceEmbedding = NLEmbedding.sentenceEmbedding(for: .english)
    private let wordEmbedding = NLEmbedding.wordEmbedding(for: .english)
    
    public init() {}
    
    public func create(request: OpenAI.EmbeddingRequest) throws -> OpenAI.EmbeddingResponse {
        let canonicalModel = ModelRegistry.resolveCanonicalId(request.model)
        let strings = request.input.strings
        
        var objects: [OpenAI.EmbeddingObject] = []
        var totalTokens = 0
        
        for (index, text) in strings.enumerated() {
            let vector: [Float]
            
            switch canonicalModel {
            case "apple-vision-featureprint":
                vector = try computeVisionFeaturePrint(from: text)
                totalTokens += 256
                
            case "apple-word-embedding":
                vector = computeWordEmbedding(for: text)
                totalTokens += text.split(separator: " ").count
                
            case "apple-sentence-embedding":
                fallthrough
            default:
                vector = computeSentenceEmbedding(for: text)
                totalTokens += text.split(separator: " ").count
            }
            
            objects.append(OpenAI.EmbeddingObject(index: index, embedding: vector))
        }
        
        let usage = OpenAI.EmbeddingResponse.Usage(promptTokens: totalTokens, totalTokens: totalTokens)
        return OpenAI.EmbeddingResponse(data: objects, model: request.model, usage: usage)
    }
    
    // MARK: - Text Embeddings
    
    public func computeSentenceEmbedding(for text: String) -> [Float] {
        if let vector = sentenceEmbedding?.vector(for: text) {
            return vector.map { Float($0) }
        }
        // Fallback: character/hash pseudo embedding of standard 512 dimension
        return generateFallbackVector(for: text, dimension: 512)
    }
    
    public func computeWordEmbedding(for text: String) -> [Float] {
        if let vector = wordEmbedding?.vector(for: text) {
            return vector.map { Float($0) }
        }
        // Fallback: character/hash pseudo embedding of standard 300 dimension
        return generateFallbackVector(for: text, dimension: 300)
    }
    
    // MARK: - Vision FeaturePrint
    
    private func computeVisionFeaturePrint(from input: String) throws -> [Float] {
        let imageData: Data
        
        if let url = URL(string: input), url.scheme != nil, let fetched = try? Data(contentsOf: url) {
            imageData = fetched
        } else if let base64Data = Data(base64Encoded: input.replacingOccurrences(of: "data:image/jpeg;base64,", with: "").replacingOccurrences(of: "data:image/png;base64,", with: "")) {
            imageData = base64Data
        } else if let fileData = try? Data(contentsOf: URL(fileURLWithPath: input)) {
            imageData = fileData
        } else {
            // If string is raw text, generate a deterministic fallback vector
            return generateFallbackVector(for: input, dimension: 768)
        }
        
        let request = VNGenerateImageFeaturePrintRequest()
        let handler = VNImageRequestHandler(data: imageData, options: [:])
        try handler.perform([request])
        
        guard let observation = request.results?.first as? VNFeaturePrintObservation else {
            return generateFallbackVector(for: input, dimension: 768)
        }
        
        let elementCount = observation.elementCount
        let floatArray: [Float] = observation.data.withUnsafeBytes { buffer in
            guard let baseAddress = buffer.bindMemory(to: Float.self).baseAddress else {
                return []
            }
            return Array(UnsafeBufferPointer(start: baseAddress, count: elementCount))
        }
        return floatArray
    }
    
    // MARK: - Fallback
    
    private func generateFallbackVector(for text: String, dimension: Int) -> [Float] {
        var hash = UInt64(5381)
        for byte in text.utf8 {
            hash = ((hash << 5) &+ hash) &+ UInt64(byte)
        }
        var vector = [Float](repeating: 0.0, count: dimension)
        for i in 0..<dimension {
            let seed = hash &+ UInt64(i &* 31)
            vector[i] = Float(Double((seed % 2000)) / 1000.0 - 1.0)
        }
        return vector
    }
}
