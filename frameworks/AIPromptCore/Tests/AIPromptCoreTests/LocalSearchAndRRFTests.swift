import XCTest
@testable import AIPromptCore

final class LocalSearchAndRRFTests: XCTestCase {

    func testReciprocalRankFusion() {
        let rrf = ReciprocalRankFusion(k: 60, lexicalWeight: 1.0, vectorWeight: 1.0)
        
        let vectorResults = [
            OpenAI.SearchResult(id: "doc1", score: 0.95, title: "Doc 1", content: "Alpha content"),
            OpenAI.SearchResult(id: "doc2", score: 0.80, title: "Doc 2", content: "Beta content"),
            OpenAI.SearchResult(id: "doc3", score: 0.70, title: "Doc 3", content: "Gamma content")
        ]
        
        let lexicalResults = [
            OpenAI.SearchResult(id: "doc2", score: 10.0, title: "Doc 2", content: "Beta content"),
            OpenAI.SearchResult(id: "doc4", score: 8.0, title: "Doc 4", content: "Delta content"),
            OpenAI.SearchResult(id: "doc1", score: 5.0, title: "Doc 1", content: "Alpha content")
        ]
        
        let fused = rrf.fuse(lexicalResults: lexicalResults, vectorResults: vectorResults, limit: 4)
        
        // Doc2: rank 2 in vector (score 1/(60+2)), rank 1 in lexical (score 1/(60+1)) -> 1/62 + 1/61 = ~0.03252
        // Doc1: rank 1 in vector (1/61), rank 3 in lexical (1/63) -> 1/61 + 1/63 = ~0.03226
        // Doc2 should be highest ranked due to being top-2 in both
        XCTAssertEqual(fused.count, 4)
        XCTAssertEqual(fused[0].id, "doc2")
        XCTAssertEqual(fused[1].id, "doc1")
    }

    func testLinearRankFusion() {
        let linear = LinearRankFusion(alpha: 0.7)
        
        let vectorResults = [
            OpenAI.SearchResult(id: "doc1", score: 1.0, title: "Doc 1", content: "Alpha"),
            OpenAI.SearchResult(id: "doc2", score: 0.5, title: "Doc 2", content: "Beta")
        ]
        
        let lexicalResults = [
            OpenAI.SearchResult(id: "doc2", score: 10.0, title: "Doc 2", content: "Beta"),
            OpenAI.SearchResult(id: "doc1", score: 2.0, title: "Doc 1", content: "Alpha")
        ]
        
        let fused = linear.fuse(lexicalResults: lexicalResults, vectorResults: vectorResults, limit: 2)
        XCTAssertEqual(fused.count, 2)
    }

    // Custom RankFusionStrategy implementation test
    struct CustomBordaCountFusion: RankFusionStrategy {
        func fuse(
            lexicalResults: [OpenAI.SearchResult],
            vectorResults: [OpenAI.SearchResult],
            limit: Int
        ) -> [OpenAI.SearchResult] {
            var scores: [String: Double] = [:]
            var sampleDoc: [String: OpenAI.SearchResult] = [:]
            
            for (idx, r) in vectorResults.enumerated() {
                scores[r.id, default: 0] += Double(vectorResults.count - idx)
                sampleDoc[r.id] = r
            }
            for (idx, r) in lexicalResults.enumerated() {
                scores[r.id, default: 0] += Double(lexicalResults.count - idx)
                sampleDoc[r.id] = r
            }
            
            let sorted = scores.sorted { $0.value > $1.value }
            return Array(sorted.prefix(limit)).compactMap { entry in
                guard var base = sampleDoc[entry.key] else { return nil }
                base.score = entry.value
                return base
            }
        }
    }

    func testCustomRankFusionStrategy() {
        let customStrategy = CustomBordaCountFusion()
        let vector = [
            OpenAI.SearchResult(id: "item1", score: 1.0, title: "T1", content: "C1"),
            OpenAI.SearchResult(id: "item2", score: 0.5, title: "T2", content: "C2")
        ]
        let lexical = [
            OpenAI.SearchResult(id: "item1", score: 1.0, title: "T1", content: "C1")
        ]
        let fused = customStrategy.fuse(lexicalResults: lexical, vectorResults: vector, limit: 2)
        XCTAssertEqual(fused.first?.id, "item1")
        XCTAssertEqual(fused.first?.score, 3.0) // 2 (from vector) + 1 (from lexical)
    }

    @MainActor
    func testIndexClientAllModes() async throws {
        let client = IndexClient()
        await client.clear()
        
        await client.add(
            id: "faq-1",
            title: "Offline AI",
            content: "Apple Foundation Models run completely offline and private on device."
        )
        await client.add(
            id: "faq-2",
            title: "Battery Health",
            content: "Optimized battery charging extends battery lifespan."
        )
        
        // 1. Vector only
        let vResults = await client.search(
            query: "private on-device machine learning",
            limit: 1,
            mode: .vectorOnly
        )
        XCTAssertEqual(vResults.first?.id, "faq-1")
        
        // 2. Spotlight only
        let sResults = await client.search(
            query: "battery charging",
            limit: 1,
            mode: .spotlightOnly
        )
        XCTAssertEqual(sResults.first?.id, "faq-2")
        
        // 3. Hybrid default RRF
        let hResults = await client.search(
            query: "private battery",
            limit: 2,
            mode: .hybrid()
        )
        XCTAssertEqual(hResults.count, 2)
        
        // 4. Hybrid with custom fusion
        let customResults = await client.search(
            query: "offline",
            limit: 1,
            mode: .hybrid(strategy: CustomBordaCountFusion())
        )
        XCTAssertEqual(customResults.first?.id, "faq-1")
        
        await client.clear()
    }
}
