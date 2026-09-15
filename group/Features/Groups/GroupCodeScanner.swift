import SwiftUI
import Vision
import VisionKit

struct GroupCodeScanner: View {
    static var isAvailable: Bool {
        DataScannerViewController.isSupported && DataScannerViewController.isAvailable
    }

    let onRecognized: (String) -> Void
    let onFailure: (String) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack(alignment: .topTrailing) {
            ScannerController(onRecognized: onRecognized, onFailure: onFailure)
                .ignoresSafeArea()

            Button("取消") { dismiss() }
                .font(.headline.weight(.black))
                .foregroundStyle(BombTheme.ink)
                .padding(.horizontal, 18)
                .frame(height: 44)
                .background(BombTheme.yellow)
                .clipShape(.capsule)
                .padding()
        }
    }
}

private struct ScannerController: UIViewControllerRepresentable {
    let onRecognized: (String) -> Void
    let onFailure: (String) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onRecognized: onRecognized, onFailure: onFailure)
    }

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let controller = DataScannerViewController(
            recognizedDataTypes: [
                .barcode(symbologies: [.qr]),
                .text(languages: ["en-US"])
            ],
            qualityLevel: .balanced,
            recognizesMultipleItems: false,
            isHighFrameRateTrackingEnabled: false,
            isPinchToZoomEnabled: true,
            isGuidanceEnabled: true,
            isHighlightingEnabled: true
        )
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ controller: DataScannerViewController, context: Context) {
        guard !controller.isScanning, !context.coordinator.hasFinished else { return }
        do {
            try controller.startScanning()
        } catch {
            context.coordinator.fail()
        }
    }

    static func dismantleUIViewController(_ controller: DataScannerViewController, coordinator: Coordinator) {
        controller.stopScanning()
    }

    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        let onRecognized: (String) -> Void
        let onFailure: (String) -> Void
        var hasFinished = false

        init(onRecognized: @escaping (String) -> Void, onFailure: @escaping (String) -> Void) {
            self.onRecognized = onRecognized
            self.onFailure = onFailure
        }

        func fail() {
            guard !hasFinished else { return }
            hasFinished = true
            DispatchQueue.main.async { [onFailure] in
                onFailure("無法啟動掃描，請確認相機權限，或手動輸入邀請碼。")
            }
        }

        func dataScanner(_ dataScanner: DataScannerViewController, becameUnavailableWithError error: DataScannerViewController.ScanningUnavailable) {
            fail()
        }

        func dataScanner(
            _ dataScanner: DataScannerViewController,
            didAdd addedItems: [RecognizedItem],
            allItems: [RecognizedItem]
        ) {
            recognize(addedItems, scanner: dataScanner)
        }

        func dataScanner(_ dataScanner: DataScannerViewController, didUpdate updatedItems: [RecognizedItem], allItems: [RecognizedItem]) {
            recognize(updatedItems, scanner: dataScanner)
        }

        private func recognize(_ items: [RecognizedItem], scanner: DataScannerViewController) {
            guard !hasFinished else { return }
            for item in items {
                let value: String?
                switch item {
                case .barcode(let barcode): value = barcode.payloadStringValue
                case .text(let text): value = text.transcript
                @unknown default: value = nil
                }
                guard let value, GroupInviteCode.isValid(value) else { continue }
                hasFinished = true
                scanner.stopScanning()
                onRecognized(GroupInviteCode.normalized(value))
                return
            }
        }
    }
}
