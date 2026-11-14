import Foundation
import ImageIO
import UniformTypeIdentifiers

public struct PreparedAvatar: Sendable { public let image: CGImage; public let png: Data }
public enum AvatarProcessor {
    public static func prepare(_ data: Data) throws -> PreparedAvatar {
        guard data.count < 10_000_000,let source = CGImageSourceCreateWithData(data as CFData,nil),
              let original = CGImageSourceCreateThumbnailAtIndex(source,0,[kCGImageSourceCreateThumbnailFromImageAlways:true,kCGImageSourceCreateThumbnailWithTransform:true,kCGImageSourceThumbnailMaxPixelSize:1024] as CFDictionary) else { throw SiteError.message("请选择 10 MB 以内的图片。") }
        let side = min(original.width,original.height)
        guard let crop = original.cropping(to:CGRect(x:(original.width-side)/2,y:(original.height-side)/2,width:side,height:side)),
              let context = CGContext(data:nil,width:100,height:100,bitsPerComponent:8,bytesPerRow:0,space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue) else { throw SiteError.invalidResponse }
        context.interpolationQuality = .high; context.draw(crop,in:CGRect(x:0,y:0,width:100,height:100))
        guard let image = context.makeImage() else { throw SiteError.invalidResponse }
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output,UTType.png.identifier as CFString,1,nil) else { throw SiteError.invalidResponse }
        CGImageDestinationAddImage(destination,image,nil)
        guard CGImageDestinationFinalize(destination) else { throw SiteError.invalidResponse }
        return PreparedAvatar(image:image,png:output as Data)
    }
}
