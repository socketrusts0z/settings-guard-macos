import AppKit
import CoreImage

/// Adds a four-module quiet zone and scales on whole pixels for crisp printing.
enum QRCodeImage {
    static func make(_ payload: String) -> CGImage? {
        guard let filter = CIFilter(name: "CIQRCodeGenerator") else { return nil }
        filter.setValue(Data(payload.utf8), forKey: "inputMessage")
        filter.setValue("M", forKey: "inputCorrectionLevel")
        guard let code = filter.outputImage else { return nil }
        let bounds = code.extent.insetBy(dx: -4, dy: -4)
        let white = CIImage(color: .white).cropped(to: bounds)
        let padded = code.composited(over: white)
            .transformed(by: CGAffineTransform(translationX: -bounds.minX, y: -bounds.minY))
            .transformed(by: CGAffineTransform(scaleX: 12, y: 12))
        return CIContext().createCGImage(padded, from: padded.extent)
    }

    static func png(_ image: CGImage) -> Data? {
        NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])
    }
}
