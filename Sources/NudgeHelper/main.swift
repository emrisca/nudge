import Foundation
import NudgeCore

print("🛡️ NudgeHelper Privileged Daemon Starting...")
// This daemon maintains charge limit registers even when UI app terminates
let manager = BatteryManager.shared
let runLoop = RunLoop.current

let timer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { _ in
    let result = manager.tick()
    // Daemon log
    // NSLog("[NudgeHelper] State: %d%%, Inhibit: %d", result.snapshot.displayPercentage, result.chargingInhibited ? 1 : 0)
}

RunLoop.current.run()
