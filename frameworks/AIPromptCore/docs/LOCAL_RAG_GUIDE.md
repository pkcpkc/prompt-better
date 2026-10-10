# Local RAG & Hybrid Retrieval Guide

`AIPromptCore` includes a complete, on-device Retrieval-Augmented Generation (RAG) and search subsystem designed specifically for iOS and macOS.

---

## 1. Dual-Engine Architecture

Local RAG combines two native Apple systems to achieve state-of-the-art retrieval accuracy completely offline:

```
                            User Query
                                │
        ┌───────────────────────┴───────────────────────┐
        ▼                                               ▼
┌─────────────────────────┐                   ┌─────────────────────────┐
│  CoreSpotlight Engine   │                   │   Vector Search Engine  │
│ (Lexical / Exact Match) │                   │  (Semantic / Embedding) │
│   - CSSearchableIndex   │                   │   - NLEmbedding         │
│   - Token Inverted Index│                   │   - Accelerate (vDSP)   │
└────────────┬────────────┘                   └────────────┬────────────┘
             │                                             │
             │ Ranked Ranks                                │ Ranked Ranks
             └───────────────────────┬─────────────────────┘
                                     ▼
                       ┌───────────────────────────┐
                       │    RankFusionStrategy     │
                       │ (Reciprocal Rank Fusion)  │
                       │       k=60, default       │
                       └─────────────┬─────────────┘
                                     ▼
                          Fused Search Results
                                     │
                                     ▼
                         Injected into AFM Prompt
```

1. **Semantic Vector Search (`VectorSearchEngine`)**:
   - Computes 512-dimensional dense embeddings using `NaturalLanguage.NLEmbedding`.
   - Normalizes vectors to unit L2 length.
   - Computes cosine similarity in parallel using hardware-accelerated SIMD vector dot products (`Accelerate.vDSP_dotpr`).
2. **Lexical String Search (`SpotlightSearchEngine`)**:
   - Indexes documents directly into Apple's native `CoreSpotlight.CSSearchableIndex`.
   - On platforms or sandbox test environments where Spotlight daemon is restricted, automatically falls back to an in-memory lexical token matcher.

---

## 2. Search Modes

When executing a search, choose between three modes via `SearchMode`:

### Mode A: Pure Semantic Vector Search (`.vectorOnly`)
```swift
let results = await client.index.search(
    query: "privacy preserving machine learning",
    limit: 5,
    mode: .vectorOnly
)
```

### Mode B: Pure String / Lexical Search (`.spotlightOnly`)
```swift
let results = await client.index.search(
    query: "invoice #9482",
    limit: 5,
    mode: .spotlightOnly
)
```

### Mode C: Pluggable Hybrid Search (`.hybrid`)
```swift
// Default Reciprocal Rank Fusion (k = 60.0)
let results = await client.index.search(
    query: "battery optimization settings",
    limit: 5,
    mode: .hybrid(k: 60.0, lexicalWeight: 1.0, vectorWeight: 1.0)
)
```

---

## 3. Pluggable Rank Fusion Strategies

The hybrid search engine decouples rank blending into the `RankFusionStrategy` protocol:

```swift
public protocol RankFusionStrategy: Sendable {
    func fuse(
        lexicalResults: [OpenAI.SearchResult],
        vectorResults: [OpenAI.SearchResult],
        limit: Int
    ) -> [OpenAI.SearchResult]
}
```

### Built-In Default: Reciprocal Rank Fusion (`ReciprocalRankFusion`)
RRF scores documents based on their reciprocal rank across lexical and vector candidate lists:

$$\text{RRF Score}(d) = \frac{w_{\text{lexical}}}{k + \text{rank}_{\text{lexical}}(d)} + \frac{w_{\text{vector}}}{k + \text{rank}_{\text{vector}}(d)}$$

where $k = 60.0$ by default.

### Built-In Alternative: Linear Score Combination (`LinearRankFusion`)
Normalizes raw cosine and lexical scores to $[0, 1]$ and computes a weighted linear sum:

$$\text{Score}(d) = \alpha \cdot \text{Score}_{\text{vector}}(d) + (1 - \alpha) \cdot \text{Score}_{\text{lexical}}(d)$$

```swift
let results = await client.index.search(
    query: "operating system updates",
    mode: .hybrid(strategy: LinearRankFusion(alpha: 0.7))
)
```

### Providing Your Own Custom Strategy
You can supply any custom rank fusion strategy (e.g., Borda count, cross-encoder reranking, BM25+decay):

```swift
struct CustomBordaFusion: RankFusionStrategy {
    func fuse(
        lexicalResults: [OpenAI.SearchResult],
        vectorResults: [OpenAI.SearchResult],
        limit: Int
    ) -> [OpenAI.SearchResult] {
        var scores: [String: Double] = [:]
        var documents: [String: OpenAI.SearchResult] = [:]

        for (rank, doc) in vectorResults.enumerated() {
            scores[doc.id, default: 0] += Double(vectorResults.count - rank)
            documents[doc.id] = doc
        }
        for (rank, doc) in lexicalResults.enumerated() {
            scores[doc.id, default: 0] += Double(lexicalResults.count - rank)
            documents[doc.id] = doc
        }

        return scores.sorted { $0.value > $1.value }
            .prefix(limit)
            .compactMap { entry in
                guard var doc = documents[entry.key] else { return nil }
                doc.score = entry.value
                return doc
            }
    }
}

// Pass directly into search
let results = await client.index.search(
    query: "financial projections",
    mode: .hybrid(strategy: CustomBordaFusion())
)
```

---

## 4. Auto-RAG in Chat Completions

When querying chat completions, you can request automatic on-device context retrieval by specifying `rag`:

```swift
let response = try await client.chat.completions.create(
    model: "omni",
    messages: [.init(role: "user", content: "What is our refund policy for digital goods?")],
    rag: .init(
        enabled: true,
        mode: "hybrid",
        limit: 3,
        minScore: 0.02
    )
)
```

The system will:
1. Search local indexes with the user query.
2. Format retrieved documents into an isolated context block.
3. Prepend the context to the AFM prompt before generation.
