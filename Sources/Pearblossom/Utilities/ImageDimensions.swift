import CoreGraphics
import Foundation
import ImageIO

/// Reads an image's pixel size without decoding it.
enum ImageDimensions {

    /// The pixel size as the photo is displayed: width and height are swapped when the EXIF
    /// orientation (5–8) turns the stored pixels a quarter turn. This matches what the canvas
    /// and export renderers draw, since both load with `.applyOrientationProperty`.
    static func orientedPixelSize(at path: String) -> CGSize? {
        guard let source = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? CGFloat,
              let height = properties[kCGImagePropertyPixelHeight] as? CGFloat else {
            return nil
        }
        let orientation = (properties[kCGImagePropertyOrientation] as? UInt32) ?? 1
        return (5...8).contains(orientation)
            ? CGSize(width: height, height: width)
            : CGSize(width: width, height: height)
    }
}
