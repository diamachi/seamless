import Foundation
@preconcurrency import IOBluetooth

struct HandsFreeEvent: Sendable {
    enum Kind: Sendable { case connected, disconnected, audioOpened, audioClosed, active, setup, held, caller, current }
    let kind: Kind
    let value: Int
    var text = ""
}

// Only value events cross to the main actor; Bluetooth objects stay in the session that owns them.
final class HandsFreeEvents: NSObject, IOBluetoothHandsFreeDeviceDelegate, @unchecked Sendable {
    let receive: @Sendable (HandsFreeEvent) -> Void
    init(receive: @escaping @Sendable (HandsFreeEvent) -> Void) { self.receive = receive }

    func handsFree(_ device: IOBluetoothHandsFree!, connected status: NSNumber!) {
        receive(HandsFreeEvent(kind: .connected, value: status.intValue))
    }
    func handsFree(_ device: IOBluetoothHandsFree!, disconnected status: NSNumber!) {
        receive(HandsFreeEvent(kind: .disconnected, value: status.intValue))
    }
    func handsFree(_ device: IOBluetoothHandsFree!, scoConnectionOpened status: NSNumber!) {
        receive(HandsFreeEvent(kind: .audioOpened, value: status.intValue))
    }
    func handsFree(_ device: IOBluetoothHandsFree!, scoConnectionClosed status: NSNumber!) {
        receive(HandsFreeEvent(kind: .audioClosed, value: status.intValue))
    }
    func handsFree(_ device: IOBluetoothHandsFreeDevice!, isCallActive value: NSNumber!) {
        receive(HandsFreeEvent(kind: .active, value: value.intValue))
    }
    func handsFree(_ device: IOBluetoothHandsFreeDevice!, callSetupMode value: NSNumber!) {
        receive(HandsFreeEvent(kind: .setup, value: value.intValue))
    }
    func handsFree(_ device: IOBluetoothHandsFreeDevice!, callHoldState value: NSNumber!) {
        receive(HandsFreeEvent(kind: .held, value: value.intValue))
    }
    func handsFree(_ device: IOBluetoothHandsFreeDevice!, incomingCallFrom number: String!) {
        receive(HandsFreeEvent(kind: .caller, value: 0, text: String((number ?? "Unknown caller").prefix(80))))
    }
    func handsFree(_ device: IOBluetoothHandsFreeDevice!, currentCall call: [AnyHashable: Any]!) {
        guard let call, let status = call[IOBluetoothHandsFreeCallStatus] as? NSNumber else { return }
        let number = call[IOBluetoothHandsFreeCallNumber] as? String ?? ""
        receive(HandsFreeEvent(kind: .current, value: status.intValue, text: String(number.prefix(80))))
    }

}
