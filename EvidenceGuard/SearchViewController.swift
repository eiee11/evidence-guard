import UIKit
import WebKit

class SearchViewController: UIViewController, WKNavigationDelegate {

    private var webView: WKWebView!
    private var logoLabel: UILabel!
    private var isRecording = false

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .white
        setupHeader()
        setupWebView()
    }

    // MARK: - Header (logo + hidden long-press trigger)

    private func setupHeader() {
        let header = UIView()
        header.backgroundColor = UIColor(red: 0.96, green: 0.96, blue: 0.96, alpha: 1.0)
        header.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(header)

        logoLabel = UILabel()
        logoLabel.text = "速搜"
        logoLabel.font = UIFont.systemFont(ofSize: 17, weight: .semibold)
        logoLabel.textColor = UIColor(red: 0.2, green: 0.5, blue: 0.9, alpha: 1.0)
        logoLabel.textAlignment = .center
        logoLabel.translatesAutoresizingMaskIntoConstraints = false
        logoLabel.isUserInteractionEnabled = true
        header.addSubview(logoLabel)

        NSLayoutConstraint.activate([
            header.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            header.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            header.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            header.heightAnchor.constraint(equalToConstant: 44),

            logoLabel.centerXAnchor.constraint(equalTo: header.centerXAnchor),
            logoLabel.centerYAnchor.constraint(equalTo: header.centerYAnchor),
            logoLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 60),
            logoLabel.heightAnchor.constraint(equalToConstant: 44)
        ])

        // Long press logo 3 seconds → toggle recording
        let longPress = UILongPressGestureRecognizer(target: self, action: #selector(handleLogoLongPress(_:)))
        longPress.minimumPressDuration = 3.0
        longPress.allowableMovement = 50
        logoLabel.addGestureRecognizer(longPress)
    }

    // MARK: - WebView (Baidu search — real and functional)

    private func setupWebView() {
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true

        webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = self
        webView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(webView)

        NSLayoutConstraint.activate([
            webView.topAnchor.constraint(equalTo: logoLabel.bottomAnchor),
            webView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            webView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])

        if let url = URL(string: "https://m.baidu.com") {
            webView.load(URLRequest(url: url))
        }
    }

    // MARK: - Long Press → Toggle Recording

    @objc private func handleLogoLongPress(_ gesture: UILongPressGestureRecognizer) {
        guard gesture.state == .began else { return }
        toggleRecording()
    }

    private func toggleRecording() {
        if isRecording {
            // Stop
            RecordingManager.shared.stopRecording()
            PiPManager.shared.stop()
            isRecording = false
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        } else {
            // Start
            RecordingManager.shared.configure()
            RecordingManager.shared.startRecording()
            PiPManager.shared.start(in: view)
            isRecording = true
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        }
    }
}

// MARK: - RecordingManagerDelegate

extension SearchViewController: RecordingManagerDelegate {

    func recordingDidStart() {
        // No UI feedback — stealth mode
    }

    func recordingDidStop(outputURL: URL?, error: Error?) {
        isRecording = false
        PiPManager.shared.stop()
        if let error = error {
            print("Recording error: \(error.localizedDescription)")
        } else if let url = outputURL {
            print("Recording saved: \(url.lastPathComponent)")
        }
    }
}
