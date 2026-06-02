import Vapor

@main
enum Entrypoint {
    static func main() async throws {
        let arguments = CommandLine.arguments
        var filteredArguments = [String]()
        var skipNext = false
        for (index, arg) in arguments.enumerated() {
            if skipNext {
                skipNext = false
                continue
            }
            if arg.hasPrefix("-NS") || arg.hasPrefix("-UI") {
                if index + 1 < arguments.count && !arguments[index + 1].hasPrefix("-") {
                    skipNext = true
                }
                continue
            }
            filteredArguments.append(arg)
        }
        
        var env = try Environment.detect(arguments: filteredArguments)
        try LoggingSystem.bootstrap(from: &env)
        
        let app = try await Application.make(env)
        defer { 
            let appCopy = app 
            Task { try await appCopy.asyncShutdown() }
        }
        
        do {
            try await configure(app)
        } catch {
            app.logger.report(error: error)
            throw error
        }
        
        try await app.execute()
    }
}
