import Foundation

public extension OpenAI {
    struct ErrorResponse: Codable, Sendable {
        public let error: ErrorDetail

        public struct ErrorDetail: Codable, Sendable {
            public let message: String
            public let type: String
            public let param: String?
            public let code: String?

            public init(message: String, type: String = "api_error", param: String? = nil, code: String? = nil) {
                self.message = message
                self.type = type
                self.param = param
                self.code = code
            }
        }

        public init(error: ErrorDetail) {
            self.error = error
        }
        
        public init(message: String, type: String = "api_error", param: String? = nil, code: String? = nil) {
            self.error = ErrorDetail(message: message, type: type, param: param, code: code)
        }
    }
}
