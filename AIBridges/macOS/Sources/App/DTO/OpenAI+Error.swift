import Vapor

extension OpenAI {
    struct ErrorResponse: Content {
        struct ErrorDetail: Codable {
            let message: String
            let type: String
            let param: String?
            let code: String?
        }
        let error: ErrorDetail
    }
}
