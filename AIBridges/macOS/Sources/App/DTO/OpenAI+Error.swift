import Vapor
import AIPromptCore

extension OpenAI.ErrorResponse: @retroactive Content {}
extension OpenAI.ErrorResponse.ErrorDetail: @retroactive Content {}
