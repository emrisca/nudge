import SwiftUI
import AppKit
import NudgeCore

@MainActor
enum NudgeScreenshotRenderer {
    static func renderAll(to outputDir: String) {
        let fm = FileManager.default
        let dirURL = URL(fileURLWithPath: outputDir, isDirectory: true)
        try? fm.createDirectory(at: dirURL, withIntermediateDirectories: true)

        let manager = BatteryManager.shared
        manager.tick()
        manager.refreshHighEnergyApps()

        let nav = NudgeNavigationController.shared
        nav.selectedSection = .overview

        // 1. Compact Menu Bar Quick Bar — Dark Moss
        let compactDark = ZStack {
            Color(hex: 0x040302)
            PopoverDashboardView(manager: manager, navigation: nav)
                .nudgeThemed(appearance: "dark")
                .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                .shadow(color: .black.opacity(0.45), radius: 18, x: 0, y: 8)
                .padding(28)
        }
        .environment(\.colorScheme, .dark)
        .fixedSize()

        render(compactDark, to: dirURL.appendingPathComponent("menubar-compact-dark.png"))

        // 2. Compact Menu Bar Quick Bar — Light Moss
        let compactLight = ZStack {
            Color(hex: 0xeef2ec)
            PopoverDashboardView(manager: manager, navigation: nav)
                .nudgeThemed(appearance: "light")
                .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                .shadow(color: .black.opacity(0.14), radius: 14, x: 0, y: 6)
                .padding(28)
        }
        .environment(\.colorScheme, .light)
        .fixedSize()

        render(compactLight, to: dirURL.appendingPathComponent("menubar-compact-light.png"))

        // 3. Full Application Dashboard — Dark Moss
        let fullDark = FullDashboardView(manager: manager, navigation: nav)
            .nudgeThemed(appearance: "dark")
            .frame(width: 1120, height: 760)
            .environment(\.colorScheme, .dark)

        render(fullDark, size: CGSize(width: 1120, height: 760), to: dirURL.appendingPathComponent("dashboard-dark.png"))

        // 5. Full Application Dashboard — Light Moss
        let fullLight = FullDashboardView(manager: manager, navigation: nav)
            .nudgeThemed(appearance: "light")
            .frame(width: 1120, height: 760)
            .environment(\.colorScheme, .light)

        render(fullLight, size: CGSize(width: 1120, height: 760), to: dirURL.appendingPathComponent("dashboard-light.png"))

        print("Rendered 4 screenshots to \(outputDir)")
    }

    private static func render<V: View>(_ view: V, size: CGSize? = nil, to url: URL) {
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2.0
        if let size {
            renderer.proposedSize = ProposedViewSize(size)
        }
        guard let cgImage = renderer.cgImage else {
            fputs("Failed to render \(url.lastPathComponent)\n", stderr)
            return
        }
        let rep = NSBitmapImageRep(cgImage: cgImage)
        rep.size = NSSize(width: CGFloat(cgImage.width) / 2.0, height: CGFloat(cgImage.height) / 2.0)
        guard let pngData = rep.representation(using: .png, properties: [:]) else {
            fputs("Failed to encode PNG \(url.lastPathComponent)\n", stderr)
            return
        }
        do {
            try pngData.write(to: url, options: .atomic)
            print("  Saved \(url.lastPathComponent) (\(cgImage.width)x\(cgImage.height))")
        } catch {
            fputs("Error writing \(url.lastPathComponent): \(error)\n", stderr)
        }
    }
}
