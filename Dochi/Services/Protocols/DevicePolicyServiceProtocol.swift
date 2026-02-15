import Foundation

@MainActor
protocol DevicePolicyServiceProtocol {
    var registeredDevices: [DeviceInfo] { get }
    var currentDevice: DeviceInfo? { get }
    var currentPolicy: DeviceSelectionPolicy { get }

    func registerCurrentDevice() async
    func updateCurrentDeviceActivity()
    func removeDevice(id: UUID)
    func renameDevice(id: UUID, name: String)
    func reorderPriority(deviceIds: [UUID])
    func evaluateResponder() -> DeviceNegotiationResult
    func shouldThisDeviceRespond() -> Bool
    func setPolicy(_ policy: DeviceSelectionPolicy)
    func setManualDevice(id: UUID)
}
