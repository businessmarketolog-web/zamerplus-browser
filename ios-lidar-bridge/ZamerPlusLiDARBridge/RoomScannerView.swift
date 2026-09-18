import SwiftUI
import UIKit
import RoomPlan
import simd

struct RoomScannerView: UIViewControllerRepresentable {
    let request: ScanRequest
    let onComplete: ([String: Any]) -> Void
    let onCancel: () -> Void

    func makeUIViewController(context: Context) -> RoomScannerViewController {
        let controller = RoomScannerViewController()
        controller.requestId = request.id
        controller.onComplete = onComplete
        controller.onCancel = onCancel
        return controller
    }

    func updateUIViewController(_ uiViewController: RoomScannerViewController, context: Context) {}
}

final class RoomScannerViewController: UIViewController, RoomCaptureViewDelegate {
    var requestId = ""
    var onComplete: (([String: Any]) -> Void)?
    var onCancel: (() -> Void)?

    private var captureView: RoomCaptureView!
    private var didFinish = false

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black

        captureView = RoomCaptureView(frame: view.bounds)
        captureView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        captureView.delegate = self
        captureView.isModelEnabled = true
        view.addSubview(captureView)

        let topBar = UIVisualEffectView(effect: UIBlurEffect(style: .systemThinMaterialDark))
        topBar.translatesAutoresizingMaskIntoConstraints = false
        topBar.layer.cornerRadius = 20
        topBar.clipsToBounds = true
        view.addSubview(topBar)

        let label = UILabel()
        label.text = "Медленно обойдите помещение. Покажите стены, двери, окна и крупные предметы с нескольких ракурсов"
        label.textColor = .white
        label.font = .systemFont(ofSize: 13, weight: .semibold)
        label.numberOfLines = 2
        label.translatesAutoresizingMaskIntoConstraints = false
        topBar.contentView.addSubview(label)

        let cancel = makeButton(title: "Отмена", color: .systemGray)
        cancel.addTarget(self, action: #selector(cancelScan), for: .touchUpInside)
        view.addSubview(одленно обойдите помещение. Покажите стены, двери, окна и крупные предметы с нескольких ракурсов"