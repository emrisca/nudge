import XCTest
@testable import NudgeCore

final class NudgeCoreTests: XCTestCase {
    func testSailingModeDeadband() {
        let engine = SailingModeEngine(targetLimit: 80, deadbandPercentage: 5) // Range: 75..80
        
        // Starts below deadband -> should charge (not sail)
        XCTAssertFalse(engine.evaluateCharging(currentPercentage: 70))
        
        // Reaches 80 -> should enter sailing (inhibit charge)
        XCTAssertTrue(engine.evaluateCharging(currentPercentage: 80))
        
        // Drops to 78 (in deadband) -> should remain sailing (inhibit charge)
        XCTAssertTrue(engine.evaluateCharging(currentPercentage: 78))
        
        // Drops to 75 (lower bound) -> should exit sailing (resume charge)
        XCTAssertFalse(engine.evaluateCharging(currentPercentage: 75))
    }

    func testHeatProtectionHysteresis() {
        let heat = HeatProtectionManager(thresholdCelsius: 35.0, hysteresisCooldownSeconds: 300.0)
        let now = Date()

        // 34C -> Normal
        XCTAssertFalse(heat.evaluateTemperature(34.0, now: now))
        
        // 36C -> Overheat triggered
        XCTAssertTrue(heat.evaluateTemperature(36.0, now: now))
        
        // 33C immediately after -> Still in 5-minute hysteresis cooldown
        let twoMinutesLater = now.addingTimeInterval(120)
        XCTAssertTrue(heat.evaluateTemperature(33.0, now: twoMinutesLater))
        
        // 33C after 6 minutes -> Recovered
        let sixMinutesLater = now.addingTimeInterval(360)
        XCTAssertFalse(heat.evaluateTemperature(33.0, now: sixMinutesLater))
    }
}
