import AVFoundation
import UIKit

protocol RecordingManagerDelegate: AnyObject {
    func recordingDidStart()
    func recordingDidStop(outputURL: URL?, error: Error?)
}

class RecordingManager: NSObject, AVCaptureFileOutputRecordingDelegate {

    static let shared = RecordingManager()

    weak var delegate: RecordingManagerDelegate?

    private let captureSession = AVCaptureSession()
    private let movieOutput = AVCaptureMovieFileOutput()
    private var currentOutputURL: URL?
    private var isConfigured = false

    var isRecording: Bool {
        return movieOutput.isRecording
    }

    private override init() {
        super.init()
    }

    // MARK: - Configuration

    func configure() {
        guard !isConfigured else { return }

        captureSession.beginConfiguration()
        captureSession.sessionPreset = .high

        // Back camera
        if let backCamera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
           let videoInput = try? AVCaptureDeviceInput(device: backCamera) {
            if captureSession.canAddInput(videoInput) {
                captureSession.addInput(videoInput)
            }
        }

        // Microphone
        if let audioDevice = AVCaptureDevice.default(for: .audio),
           let audioInput = try? AVCaptureDeviceInput(device: audioDevice) {
            if captureSession.canAddInput(audioInput) {
                captureSession.addInput(audioInput)
            }
        }

        // Movie file output
        if captureSession.canAddOutput(movieOutput) {
            captureSession.addOutput(movieOutput)
        }

        captureSession.commitConfiguration()
        isConfigured = true
    }

    // MARK: - Recording Control

    func startRecording() {
        guard !isRecording else { return }

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }

            if !self.captureSession.isRunning {
                self.captureSession.startRunning()
            }

            // Output path
            let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
            let dir = docs.appendingPathComponent("recordings", isDirectory: true)
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

            let ts = Int(Date().timeIntervalSince1970)
            let url = dir.appendingPathComponent("REC_\(ts).mp4")
            self.currentOutputURL = url

            DispatchQueue.main.async {
                self.movieOutput.startRecording(to: url, recordingDelegate: self)
                self.delegate?.recordingDidStart()
            }
        }
    }

    func stopRecording() {
        guard isRecording else { return }
        movieOutput.stopRecording()
    }

    // MARK: - AVCaptureFileOutputRecordingDelegate

    func fileOutput(
        _ output: AVCaptureFileOutput,
        didFinishRecordingTo outputFileURL: URL,
        from connections: [AVCaptureConnection],
        error: Error?
    ) {
        if captureSession.isRunning {
            captureSession.stopRunning()
        }

        delegate?.recordingDidStop(outputURL: error == nil ? outputFileURL : nil, error: error)
    }
}
