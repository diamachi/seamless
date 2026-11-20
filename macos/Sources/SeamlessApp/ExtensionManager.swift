// macOS application presentation and coordination for extension manager.
// See docs/ARCHITECTURE.md for the owning subsystem and cross-platform call flow.

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
    /// Performs install for extension manager.
    func install() {
        guard isBundled else { return }
        let request = OSSystemExtensionRequest.activationRequest(forExtensionWithIdentifier: Self.cameraIdentifier, queue: .main)
        request.delegate = self
        OSSystemExtensionManager.shared.submitRequest(request)
    }
    /// Performs uninstall for extension manager.
    func uninstall() {
        let request = OSSystemExtensionRequest.deactivationRequest(forExtensionWithIdentifier: Self.cameraIdentifier, queue: .main)
        request.delegate = self
        OSSystemExtensionManager.shared.submitRequest(request)
    }
    /// Performs request needs user approval for extension manager.
    func requestNeedsUserApproval(_ request: OSSystemExtensionRequest) { message = "Approve Seamless Camera in macOS System Settings to continue." }
    /// Performs request for extension manager.
    func request(_ request: OSSystemExtensionRequest, didFinishWithResult result: OSSystemExtensionRequest.Result) {
        message = result == .completed ? "Extension request completed." : "Restart the Mac to finish the extension request."
    }
    /// Performs request for extension manager.
    func request(_ request: OSSystemExtensionRequest, didFailWithError error: any Error) { message = error.localizedDescription }
    /// Performs request for extension manager.
    func request(_ request: OSSystemExtensionRequest, actionForReplacingExtension existing: OSSystemExtensionProperties, withExtension replacement: OSSystemExtensionProperties) -> OSSystemExtensionRequest.ReplacementAction { .replace }
}
