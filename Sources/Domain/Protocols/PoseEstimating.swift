import CoreVideo

protocol PoseEstimating {
    func estimatePose(in pixelBuffer: CVPixelBuffer) throws -> PoseFrame?
}
