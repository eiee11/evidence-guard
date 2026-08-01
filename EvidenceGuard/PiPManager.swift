import AVFoundation
import AVKit
import UIKit
import CoreVideo
import CoreMedia

/// Manages Picture-in-Picture keep-alive during background recording.
/// Feeds black sample buffers to an AVSampleBufferDisplayLayer,
/// then starts AVPictureInPictureController so the app process
/// stays alive when backgrounded — letting AVCaptureSession keep writing.
class PiPManager: NSObject {

    static let shared = PiPManager()

    private var sampleBufferDisplayLayer: AVSampleBufferDisplayLayer?
    private var pipController: AVPictureInPictureController?
    private var displayLink: CADisplayLink?
    private var pixelBufferPool: CVPixelBufferPool?
    private var frameCounter: CMTimeValue = 0
    private var setupRetryCount = 0

    private override init() {
        super.init()
    }

    // MARK: - Audio Session (call BEFORE starting capture session)

    func configureAudioSession() {
        do {
            try AVAudioSession.sharedInstance().setCategory(
                .playAndRecord,
                mode: .videoRecording,
                options: [.mixWithOthers, .allowBluetooth]
            )
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            print("Audio session error: \(error)")
        }
    }

    // MARK: - Start / Stop

    func start(in hostView: UIView) {
        // 1. Pixel buffer pool for 1×1 black frames
        createPixelBufferPool()

        // 2. Sample-buffer display layer (hidden behind webview)
        let layer = AVSampleBufferDisplayLayer()
        layer.frame = CGRect(x: 0, y: 0, width: 2, height: 2)
        hostView.layer.insertSublayer(layer, at: 0)
        self.sampleBufferDisplayLayer = layer

        // 3. Feed black frames at ~30 fps
        frameCounter = 0
        displayLink = CADisplayLink(target: self, selector: #selector(feedBlackFrame))
        displayLink?.preferredFramesPerSecond = 30
        displayLink?.add(to: .main, forMode: .common)

        // 4. Create PiP controller after a few frames are queued
        setupRetryCount = 0
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            self?.trySetupPiPController()
        }
    }

    func stop() {
        displayLink?.invalidate()
        displayLink = nil

        pipController?.stopPictureInPicture()
        pipController = nil

        sampleBufferDisplayLayer?.flush()
        sampleBufferDisplayLayer?.removeFromSuperlayer()
        sampleBufferDisplayLayer = nil

        pixelBufferPool = nil
    }

    // MARK: - Pixel Buffer Pool

    private func createPixelBufferPool() {
        let attrs: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: 1,
            kCVPixelBufferHeightKey as String: 1,
            kCVPixelBufferIOSurfacePropertiesKey as String: [:] as [String: Any]
        ]
        var pool: CVPixelBufferPool?
        CVPixelBufferPoolCreate(kCFAllocatorDefault, nil, attrs as CFDictionary, &pool)
        self.pixelBufferPool = pool
    }

    // MARK: - Feed Black Frames

    @objc private func feedBlackFrame() {
        guard let layer = sampleBufferDisplayLayer, layer.status != .failed else { return }
        guard let buf = createBlackSampleBuffer() else { return }
        layer.enqueue(buf)
    }

    private func createBlackSampleBuffer() -> CMSampleBuffer? {
        guard let pool = pixelBufferPool else { return nil }

        var pixelBuffer: CVPixelBuffer?
        let st = CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, pool, &pixelBuffer)
        guard st == kCVReturnSuccess, let pb = pixelBuffer else { return nil }

        // Paint black
        CVPixelBufferLockBaseAddress(pb, [])
        if let base = CVPixelBufferGetBaseAddress(pb) {
            memset(base, 0, CVPixelBufferGetDataSize(pb))
        }
        CVPixelBufferUnlockBaseAddress(pb, [])

        // Format description
        var fmt: CMVideoFormatDescription?
        CMVideoFormatDescriptionCreateForImageBuffer(
            allocator: kCFAllocatorDefault,
            imageBuffer: pb,
            formatDescriptionOut: &fmt
        )
        guard let fd = fmt else { return nil }

        // Timing
        let pts = CMTime(value: frameCounter, timescale: 30)
        frameCounter += 1
        var timing = CMSampleTimingInfo(
            duration: CMTime(value: 1, timescale: 30),
            presentationTimeStamp: pts,
            decodeTimeStamp: .invalid
        )

        var sampleBuffer: CMSampleBuffer?
        let bs = CMSampleBufferCreateReadyWithImageBuffer(
            allocator: kCFAllocatorDefault,
            imageBuffer: pb,
            formatDescription: fd,
            sampleTiming: &timing,
            sampleBufferOut: &sampleBuffer
        )
        guard bs == noErr, let sb = sampleBuffer else { return nil }

        return sb
    }

    // MARK: - PiP Controller

    private func trySetupPiPController() {
        guard let layer = sampleBufferDisplayLayer else { return }

        if layer.status == .failed {
            layer.flush()
            setupRetryCount += 1
            if setupRetryCount < 5 {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                    self?.trySetupPiPController()
                }
            }
            return
        }

        guard AVPictureInPictureController.isPictureInPictureSupported() else {
            print("PiP not supported")
            return
        }

        let source = AVPictureInPictureController.ContentSource(
            sampleBufferDisplayLayer: layer,
            playbackDelegate: self
        )

        pipController = AVPictureInPictureController(contentSource: source)
        pipController?.delegate = self
        pipController?.canStartPictureInPictureAutomaticallyFromInline = true

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            self?.pipController?.startPictureInPicture()
        }
    }
}

// MARK: - AVPictureInPictureControllerDelegate

extension PiPManager: AVPictureInPictureControllerDelegate {

    func pictureInPictureController(
        _ c: AVPictureInPictureController,
        failedToStartPictureInPictureWithError error: Error
    ) {
        print("PiP start failed: \(error.localizedDescription)")
    }
}

// MARK: - AVPictureInPictureSampleBufferPlaybackDelegate

extension PiPManager: AVPictureInPictureSampleBufferPlaybackDelegate {

    func pictureInPictureController(
        _ c: AVPictureInPictureController,
        setPlaying playing: Bool
    ) {
        // Always "playing"
    }

    func pictureInPictureControllerTimeRangeForPlayback(
        _ c: AVPictureInPictureController
    ) -> CMTimeRange {
        return CMTimeRange(start: .negativeInfinity, duration: .positiveInfinity)
    }

    func pictureInPictureControllerIsPlaybackPaused(
        _ c: AVPictureInPictureController
    ) -> Bool {
        return false
    }

    func pictureInPictureController(
        _ c: AVPictureInPictureController,
        didTransitionToRenderSize newRenderSize: CMVideoDimensions
    ) {}

    func pictureInPictureController(
        _ c: AVPictureInPictureController,
        skipByInterval skipInterval: CMTime,
        completion completionHandler: @escaping () -> Void
    ) {
        completionHandler()
    }
}
