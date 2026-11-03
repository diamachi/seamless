import Foundation
import SystemExtensions

@MainActor
final class ExtensionManager: NSObject, ObservableObject, @preconcurrency OSSystemExtensionRequestDelegate {
    static let cameraIdentifier = "dev.seamless.mac.camera"
    @Published private(set) var message = "System webcam installation needs the signed Seamless Camera extension. This development bundle does not contain it yet."
    var isBundled: Bool {
        let directory = Bundle.main.bundleURL.appendingPathComponent("Contents/Library/SystemExtensions")
        return (try? FileManager.default.contentsOfDirectory(atPath: directory.path).contains { $0.hasSuffix(".systemextension") }) == true
    }
    func install() {
        guard isBundled else { return }
        let request = OSSystemExtensionRequest.activationRequest(forExtensionWithIdentifier: Self.cameraIdentifier, queue: .main)
        request.delegate = self
        OSSystemExtensionManager.shared.submitRequest(request)
    }
    func uninstall() {
        let request = OSSystemExtensionRequest.deactivationRequest(forExtensionWithIdentifier: Self.cameraIdentifier, queue: .main)
        request.delegate = self
        OSSystemExtensionManager.shared.submitRequest(request)
    }
    func requestNeedsUserApproval(_ request: OSSystemExtensionRequest) { message = "Approve Seamless Camera in macOS System Settings to continue." }
    func request(_ request: OSSystemExtensionRequest, didFinishWithResult result: OSSystemExtensionRequest.Result) {
        message = result == .completed ? "Extension request completed." : "Restart the Mac to finish the extension request."
    }
    func request(_ request: OSSystemExtensionRequest, didFailWithError error: any Error) { message = error.localizedDescription }
    func request(_ request: OSSystemExtensionRequest, actionForReplacingExtension existing: OSSystemExtensionProperties, withExtension replacement: OSSystemExtensionProperties) -> OSSystemExtensionRequest.ReplacementAction { .replace }
}
