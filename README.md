# Nudge ⚡

Production-grade macOS battery care, health, and charge management utility for Apple Silicon & Intel MacBooks.

## Features
- **Charge Limiter**: Hardware-level SMC intervention to halt charging at a target limit (e.g. 80%).
- **Sailing Mode**: Deadband control (5–10%) below target limit to eliminate micro-cycling.
- **Heat Protection**: Real-time IOKit battery temperature monitoring with 5-minute hysteresis cooldown.
- **Calibration Mode**: Automated 4-phase battery calibration cycle (100% → 10% → 100% → target limit).
- **Automatic Discharge**: Drains battery toward target threshold while physically connected to power.
- **Privileged Background Daemon**: Keeps charging limits active across Fast User Switching, sleep transitions, and app closures.
- **Power Flow Analytics**: Live wattage telemetry (Charger in, Battery net, System load).

## Architecture
- **NudgeCore**: Swift package interfacing with IOKit (`IOPowerSources`, `AppleSmartBattery`) and SMC keys.
- **NudgeCLI**: Command-line interface for querying and driving power states.
- **NudgeHelper**: Lightweight privileged daemon for always-on enforcement.
