import Foundation
import IOKit.pwr_mgt
@MainActor public protocol PowerManaging: AnyObject {
    func acquire() throws
    func release()
}
@MainActor public final class PowerAssertion: PowerManaging {
    private var id: IOPMAssertionID = 0
    public init() {}
    public func acquire() throws {
        guard id == 0 else { return }
        let result = IOPMAssertionCreateWithName(kIOPMAssertionTypePreventUserIdleSystemSleep as CFString, IOPMAssertionLevel(kIOPMAssertionLevelOn), "Lecture recording or local transcription" as CFString, &id)
        guard result == kIOReturnSuccess else { id = 0; throw StorageFailure.invalidData("Could not keep this Mac awake for recording.") }
    }
    public func release() { if id != 0 { IOPMAssertionRelease(id); id = 0 } }
}
