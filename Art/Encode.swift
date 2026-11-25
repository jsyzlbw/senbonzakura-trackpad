import Foundation
import AVFoundation
import CoreGraphics
import CoreVideo
import Darwin

enum RenderError: Error { case invalidInput, pixelBuffer, context, encoder(String) }

@main struct Encode {
    static func main() throws {
        let args = CommandLine.arguments
        guard args.count == 4, let first = Int(args[2]), let end = Int(args[3]), first < end else { throw RenderError.invalidInput }
        let writer = try AVAssetWriter(outputURL: URL(fileURLWithPath: args[1]), fileType: .mp4)
        let width = 1920, height = 1080
        let settings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: width, AVVideoHeightKey: height,
            AVVideoCompressionPropertiesKey: [AVVideoAverageBitRateKey: 10500000, AVVideoMaxKeyFrameIntervalKey: 60,
                                              AVVideoAllowFrameReorderingKey: false],
            AVVideoColorPropertiesKey: [AVVideoColorPrimariesKey: AVVideoColorPrimaries_ITU_R_709_2,
                                        AVVideoTransferFunctionKey: AVVideoTransferFunction_ITU_R_709_2,
                                        AVVideoYCbCrMatrixKey: AVVideoYCbCrMatrix_ITU_R_709_2]]
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
        let attrs: [String: Any] = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                                    kCVPixelBufferWidthKey as String: width, kCVPixelBufferHeightKey as String:height,
                                    kCVPixelBufferIOSurfacePropertiesKey as String: [:]]
        let adapter = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: attrs)
        writer.add(input)
        guard writer.startWriting() else { throw writer.error ?? RenderError.encoder("start") }
        writer.startSession(atSourceTime: .zero)
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        for frame in first..<end {
            try autoreleasepool {
                while !input.isReadyForMoreMediaData {
                    guard writer.status == .writing else { throw writer.error ?? RenderError.encoder("stopped") }
                    usleep(1500)
                }
                var candidate: CVPixelBuffer?
                guard let pool = adapter.pixelBufferPool, CVPixelBufferPoolCreatePixelBuffer(nil,pool,&candidate)==kCVReturnSuccess, let pixel=candidate else { throw RenderError.pixelBuffer }
                CVPixelBufferLockBaseAddress(pixel, [])
                do {
                    defer { CVPixelBufferUnlockBaseAddress(pixel, []) }
                    let layout = CGImageAlphaInfo.noneSkipFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
                    guard let ctx=CGContext(data:CVPixelBufferGetBaseAddress(pixel),width:width,height:height,bitsPerComponent:8,bytesPerRow:CVPixelBufferGetBytesPerRow(pixel),space:space,bitmapInfo:layout) else { throw RenderError.context }
                    ctx.translateBy(x:0,y:CGFloat(height)); ctx.scaleBy(x:1,y:-1)
                    drawMV(ctx,Double(frame)/30)
                }
                guard adapter.append(pixel, withPresentationTime:CMTime(value:Int64(frame-first),timescale:30)) else { throw writer.error ?? RenderError.encoder("append") }
            }
            if (frame-first)%450==0 { print("frame",frame); fflush(stdout) }
        }
        writer.endSession(atSourceTime: CMTime(value:Int64(end-first),timescale:30))
        input.markAsFinished()
        let done=DispatchSemaphore(value:0)
        writer.finishWriting { done.signal() }
        done.wait()
        guard writer.status == .completed else { throw writer.error ?? RenderError.encoder("finish") }
    }
}
