import AVFoundation
import SwiftUI

struct TVCameraPreviewView: UIViewRepresentable {
    let session: AVCaptureSession

    func makeUIView(context: Context) -> TVPreviewView {
        let view = TVPreviewView()
        view.previewLayer.videoGravity = .resizeAspect
        view.previewLayer.session = session
        view.backgroundColor = .black
        return view
    }

    func updateUIView(_ uiView: TVPreviewView, context: Context) {
        uiView.previewLayer.session = session
    }
}

final class TVPreviewView: UIView {
    override class var layerClass: AnyClass {
        AVCaptureVideoPreviewLayer.self
    }

    var previewLayer: AVCaptureVideoPreviewLayer {
        guard let layer = layer as? AVCaptureVideoPreviewLayer else {
            fatalError("Expected AVCaptureVideoPreviewLayer")
        }
        return layer
    }
}
