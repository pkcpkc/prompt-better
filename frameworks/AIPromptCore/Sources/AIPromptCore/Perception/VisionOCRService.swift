import Foundation
import Vision
import PDFKit

#if canImport(AppKit)
import AppKit
#endif

#if canImport(UIKit)
import UIKit
#endif

/// In-process OCR and PDF extraction service using Apple's Vision framework and PDFKit.
public final class VisionOCRService: @unchecked Sendable {
    public static let shared = VisionOCRService()
    
    public init() {}
    
    /// Recognizes text from image data using on-device VNRecognizeTextRequest.
    public func recognizeText(from imageData: Data) async throws -> String {
        guard !imageData.isEmpty else { return "" }
        
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        
        let handler = VNImageRequestHandler(data: imageData, options: [:])
        do {
            try handler.perform([request])
        } catch {
            throw AIError.unsupportedOperation("Could not read the image for OCR: \(error.localizedDescription)")
        }
        
        guard let observations = request.results else {
            return ""
        }
        
        let recognizedStrings = observations.compactMap { observation in
            observation.topCandidates(1).first?.string
        }
        
        return recognizedStrings.joined(separator: "\n")
    }
    
    /// Recognizes text from an image URL (file URL or base64 data URI).
    public func recognizeText(fromURL urlString: String) async throws -> String {
        return try await recognizeText(from: ImageLoading.data(fromReference: urlString))
    }
    
    /// Extracts text from a PDF document using PDFKit.
    public func extractText(fromPDF pdfData: Data) throws -> String {
        guard let document = PDFDocument(data: pdfData) else {
            throw AIError.unsupportedOperation("Failed to load PDF document.")
        }
        
        var pagesText: [String] = []
        for i in 0..<document.pageCount {
            if let page = document.page(at: i), let text = page.string?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty {
                pagesText.append("[Page \(i + 1)]\n\(text)")
            }
        }
        
        return pagesText.joined(separator: "\n\n")
    }
}
