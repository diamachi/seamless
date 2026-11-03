import CryptoKit
import Foundation
import Network
import Security
import SeamlessCore

enum PinnedTLSConnection {
    static func make(profile: ConnectionProfile) throws -> NWConnection {
        guard let port = NWEndpoint.Port(rawValue: profile.port), !profile.host.isEmpty,
              profile.certificatePin.count == 64 else { throw ConnectionProtocolError.invalidInvitation }
        let options = NWProtocolTLS.Options()
        sec_protocol_options_set_min_tls_protocol_version(options.securityProtocolOptions, .TLSv12)
        let expectedPin = profile.certificatePin.lowercased()
        sec_protocol_options_set_verify_block(options.securityProtocolOptions, { _, trustObject, completion in
            let trust = sec_trust_copy_ref(trustObject).takeRetainedValue()
            guard let certificates = SecTrustCopyCertificateChain(trust) as? [SecCertificate],
                  let certificate = certificates.first else { completion(false); return }
            let bytes = SecCertificateCopyData(certificate) as Data
            let pin = SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
            completion(pin == expectedPin)
        }, DispatchQueue.global(qos: .userInitiated))
        return NWConnection(host: NWEndpoint.Host(profile.host), port: port, using: NWParameters(tls: options))
    }
}
