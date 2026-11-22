import SwiftUI
import AppKit
import NudgeCore

/// Full Moss-styled GitHub Releases updater card for SettingsView.
public struct UpdateSettingsCard: View {
    @Environment(\.nudgePalette) private var palette
    @ObservedObject var updater: UpdateManager

    public init(updater: UpdateManager) {
        self.updater = updater
    }

    private let intervalOptions: [(label: String, hours: Int)] = [
        ("Every 6h", 6),
        ("Daily", 24),
        ("Weekly", 168)
    ]

    public var body: some View {
        NudgeCard(
            title: "Software Updates",
            subtitle: "Follow new releases from GitHub (\(NudgeVersion.repositoryOwner)/\(NudgeVersion.repositoryName))",
            symbol: "arrow.triangle.2.circlepath.circle.fill"
        ) {
            VStack(alignment: .leading, spacing: 14) {
                statusHeaderRow

                stateDetailPanel

                actionButtonRow

                NudgeSectionDivider()

                preferencesSection
            }
        }
    }

    // MARK: - Status Header

    private var statusHeaderRow: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text("Installed Version")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(palette.foreground)
                    Text("v\(updater.currentVersionString)")
                        .nudgeMetricFont(size: 11.5, weight: .bold)
                        .foregroundStyle(palette.primary)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(
                            Capsule(style: .continuous)
                                .fill(palette.primary.opacity(0.14))
                        )
                    Text(NudgeVersion.currentArchitecture)
                        .nudgeMetricFont(size: 10, weight: .semibold)
                        .foregroundStyle(palette.mutedForeground)
                }

                Text(lastCheckedDescription)
                    .font(.system(size: 11))
                    .foregroundStyle(palette.mutedForeground)
            }

            Spacer()

            statusBadge
        }
    }

    @ViewBuilder
    private var statusBadge: some View {
        switch updater.state {
        case .idle:
            badgePill(text: "Ready", color: palette.mutedForeground, bg: palette.muted)
        case .checking:
            HStack(spacing: 6) {
                ProgressView()
                    .controlSize(.small)
                    .scaleEffect(0.75)
                Text("Checking…")
                    .font(.system(size: 11, weight: .semibold))
            }
            .foregroundStyle(palette.foreground)
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background(Capsule(style: .continuous).fill(palette.muted))
        case .upToDate:
            badgePill(text: "Up to Date", color: palette.statusPositive, bg: palette.statusPositive.opacity(0.14))
        case .updateAvailable(let release):
            badgePill(text: "\(release.displayVersion) Available", color: palette.primaryForeground, bg: palette.primary)
        case .downloading(_, let progress, _, _):
            badgePill(text: "Downloading \(Int(round(progress * 100)))%", color: palette.primary, bg: palette.primary.opacity(0.14))
        case .verifying:
            badgePill(text: "Verifying SHA-256…", color: palette.primary, bg: palette.primary.opacity(0.14))
        case .installing:
            badgePill(text: "Installing…", color: palette.primary, bg: palette.primary.opacity(0.14))
        case .readyToRelaunch:
            badgePill(text: "Relaunching…", color: palette.statusPositive, bg: palette.statusPositive.opacity(0.14))
        case .downloadedInstaller:
            badgePill(text: "Downloaded", color: palette.statusPositive, bg: palette.statusPositive.opacity(0.14))
        case .failed:
            badgePill(text: "Check Failed", color: palette.destructive, bg: palette.destructive.opacity(0.14))
        }
    }

    private func badgePill(text: String, color: Color, bg: Color) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background(Capsule(style: .continuous).fill(bg))
    }

    // MARK: - Dynamic State Detail Panel

    @ViewBuilder
    private var stateDetailPanel: some View {
        switch updater.state {
        case .updateAvailable(let release):
            releaseInfoBox(release: release, progress: nil, statusLine: nil)

        case .downloading(let release, let progress, let received, let total):
            let byteSummary = total > 0
                ? "\(ByteCountFormatter.string(fromByteCount: received, countStyle: .file)) / \(ByteCountFormatter.string(fromByteCount: total, countStyle: .file))"
                : ByteCountFormatter.string(fromByteCount: received, countStyle: .file)
            releaseInfoBox(
                release: release,
                progress: progress,
                statusLine: "Downloading \(release.displayVersion) (\(byteSummary))…"
            )

        case .verifying(let release):
            releaseInfoBox(
                release: release,
                progress: 1.0,
                statusLine: "Verifying SHA-256 checksum against release manifest…"
            )

        case .installing(let release):
            releaseInfoBox(
                release: release,
                progress: 1.0,
                statusLine: "Extracting verified bundle and preparing relaunch…"
            )

        case .readyToRelaunch(let release):
            releaseInfoBox(
                release: release,
                progress: 1.0,
                statusLine: "Update \(release.displayVersion) installed. Relaunching Nudge…"
            )

        case .downloadedInstaller(let release, let fileURL):
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(palette.statusPositive)
                    Text("Downloaded \(release.displayVersion) to \(fileURL.lastPathComponent)")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(palette.foreground)
                }
                Text("Because this instance is not running from a writable .app bundle, open the downloaded installer to finish updating.")
                    .font(.system(size: 11))
                    .foregroundStyle(palette.mutedForeground)
                HStack(spacing: 8) {
                    Button {
                        NSWorkspace.shared.activateFileViewerSelecting([fileURL])
                    } label: {
                        Label("Reveal in Finder", systemImage: "folder.fill")
                    }
                    .buttonStyle(NudgePrimaryButtonStyle())

                    Button {
                        NSWorkspace.shared.open(fileURL)
                    } label: {
                        Label("Open Installer", systemImage: "arrow.up.forward.square")
                    }
                    .buttonStyle(NudgeSecondaryButtonStyle())
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: NudgeMetrics.controlRadius, style: .continuous)
                    .fill(palette.muted.opacity(0.65))
            )
            .overlay(
                RoundedRectangle(cornerRadius: NudgeMetrics.controlRadius, style: .continuous)
                    .strokeBorder(palette.border, lineWidth: 1)
            )

        case .failed(let message):
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 13))
                    .foregroundStyle(palette.destructive)
                    .padding(.top, 1)
                Text(message)
                    .font(.system(size: 11.5))
                    .foregroundStyle(palette.foreground)
                    .textSelection(.enabled)
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: NudgeMetrics.controlRadius, style: .continuous)
                    .fill(palette.destructive.opacity(0.10))
            )
            .overlay(
                RoundedRectangle(cornerRadius: NudgeMetrics.controlRadius, style: .continuous)
                    .strokeBorder(palette.destructive.opacity(0.35), lineWidth: 1)
            )

        default:
            EmptyView()
        }
    }

    private func releaseInfoBox(release: GitHubRelease, progress: Double?, statusLine: String?) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(release.name.isEmpty ? "Nudge \(release.displayVersion)" : release.name)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(palette.foreground)
                if release.prerelease {
                    Text("Pre-release")
                        .font(.system(size: 9.5, weight: .semibold))
                        .foregroundStyle(palette.warning)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(palette.warning.opacity(0.14)))
                }
                Spacer()
                if let published = release.publishedAt {
                    Text(published, style: .date)
                        .font(.system(size: 10.5))
                        .foregroundStyle(palette.mutedForeground)
                }
            }

            if !release.body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                ScrollView(.vertical, showsIndicators: true) {
                    Text(release.body.trimmingCharacters(in: .whitespacesAndNewlines))
                        .font(.system(size: 11.5))
                        .foregroundStyle(palette.mutedForeground)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                }
                .frame(maxHeight: 110)
            }

            if let progress {
                VStack(alignment: .leading, spacing: 4) {
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule(style: .continuous).fill(palette.muted)
                            Capsule(style: .continuous)
                                .fill(palette.primary)
                                .frame(width: max(6, geo.size.width * CGFloat(min(1, max(0, progress)))))
                        }
                    }
                    .frame(height: 6)

                    if let statusLine {
                        Text(statusLine)
                            .font(.system(size: 10.5, weight: .medium))
                            .foregroundStyle(palette.mutedForeground)
                    }
                }
            } else {
                HStack(spacing: 8) {
                    Button {
                        Task { await updater.downloadAndInstallUpdate(release) }
                    } label: {
                        Label("Install & Relaunch", systemImage: "arrow.down.circle.fill")
                    }
                    .buttonStyle(NudgePrimaryButtonStyle())

                    Button {
                        NSWorkspace.shared.open(release.htmlURL)
                    } label: {
                        Label("Release Notes", systemImage: "arrow.up.right.square")
                    }
                    .buttonStyle(NudgeSecondaryButtonStyle())

                    Spacer()

                    Button {
                        updater.skipVersion(release.tagName)
                    } label: {
                        Text("Skip \(release.displayVersion)")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(palette.mutedForeground)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: NudgeMetrics.controlRadius, style: .continuous)
                .fill(palette.muted.opacity(0.6))
        )
        .overlay(
            RoundedRectangle(cornerRadius: NudgeMetrics.controlRadius, style: .continuous)
                .strokeBorder(palette.primary.opacity(0.35), lineWidth: 1)
        )
    }

    // MARK: - Primary Action Row

    private var actionButtonRow: some View {
        HStack(spacing: 8) {
            Button {
                Task { await updater.checkForUpdates(userInitiated: true) }
            } label: {
                Label(
                    updater.state == .checking ? "Checking…" : "Check for Updates",
                    systemImage: "arrow.clockwise"
                )
            }
            .buttonStyle(NudgeSecondaryButtonStyle())
            .disabled(updater.state.isBusy)

            Button {
                NSWorkspace.shared.open(NudgeVersion.releasesPageURL)
            } label: {
                Label("GitHub Releases", systemImage: "safari")
            }
            .buttonStyle(NudgeSecondaryButtonStyle())

            Spacer()

            if let skipped = updater.skippedVersion {
                Button {
                    updater.clearSkippedVersion()
                    Task { await updater.checkForUpdates(userInitiated: true) }
                } label: {
                    Text("Reset skipped (\(skipped))")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(palette.mutedForeground)
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Preferences

    private var preferencesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Toggle(
                isOn: Binding(
                    get: { updater.automaticChecksEnabled },
                    set: { updater.automaticChecksEnabled = $0 }
                )
            ) {
                VStack(alignment: .leading, spacing: 1) {
                    Text("Automatically check for updates")
                        .font(.system(size: 12.5, weight: .medium))
                    Text("Periodically poll GitHub Releases in the background while Nudge runs")
                        .font(.system(size: 11))
                        .foregroundStyle(palette.mutedForeground)
                }
            }
            .toggleStyle(NudgeSwitchToggleStyle())

            if updater.automaticChecksEnabled {
                HStack(spacing: 8) {
                    Text("Check Frequency")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(palette.foreground)
                    Spacer()
                    HStack(spacing: 4) {
                        ForEach(intervalOptions, id: \.hours) { option in
                            let isSelected = updater.checkIntervalHours == option.hours
                            Button {
                                updater.checkIntervalHours = option.hours
                            } label: {
                                Text(option.label)
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(isSelected ? palette.primaryForeground : palette.foreground)
                                    .padding(.horizontal, 9)
                                    .padding(.vertical, 5)
                                    .background(
                                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                                            .fill(isSelected ? palette.primary : palette.muted)
                                    )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }

            Toggle(
                isOn: Binding(
                    get: { updater.includePrereleases },
                    set: { updater.includePrereleases = $0 }
                )
            ) {
                VStack(alignment: .leading, spacing: 1) {
                    Text("Include pre-releases")
                        .font(.system(size: 12.5, weight: .medium))
                    Text("Follow beta and release-candidate tags published on GitHub")
                        .font(.system(size: 11))
                        .foregroundStyle(palette.mutedForeground)
                }
            }
            .toggleStyle(NudgeSwitchToggleStyle())
        }
    }

    private var lastCheckedDescription: String {
        guard let last = updater.lastCheckedAt else {
            return "Not checked yet"
        }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return "Last checked \(formatter.localizedString(for: last, relativeTo: Date()))"
    }
}

/// Compact Moss update notification banner shown inside the expanded menu bar popover when a new release is available.
public struct PopoverUpdateBanner: View {
    @Environment(\.nudgePalette) private var palette
    @ObservedObject var updater: UpdateManager

    public init(updater: UpdateManager) {
        self.updater = updater
    }

    public var body: some View {
        switch updater.state {
        case .updateAvailable(let release):
            HStack(spacing: 10) {
                Image(systemName: "arrow.down.circle.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(palette.primary)

                VStack(alignment: .leading, spacing: 1) {
                    Text("Nudge \(release.displayVersion) available")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(palette.foreground)
                    Text("Ready to download & verify from GitHub")
                        .font(.system(size: 10.5))
                        .foregroundStyle(palette.mutedForeground)
                }

                Spacer(minLength: 4)

                Button {
                    Task { await updater.downloadAndInstallUpdate(release) }
                } label: {
                    Text("Update")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(palette.primaryForeground)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Capsule(style: .continuous).fill(palette.primary))
                }
                .buttonStyle(.plain)

                Button {
                    NSWorkspace.shared.open(release.htmlURL)
                } label: {
                    Image(systemName: "arrow.up.right.square")
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundStyle(palette.mutedForeground)
                }
                .buttonStyle(.plain)
                .help("View release on GitHub")

                Button {
                    updater.skipVersion(release.tagName)
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(palette.mutedForeground)
                }
                .buttonStyle(.plain)
                .help("Skip \(release.displayVersion)")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(
                RoundedRectangle(cornerRadius: NudgeMetrics.controlRadius, style: .continuous)
                    .fill(palette.primary.opacity(palette.isDark ? 0.16 : 0.11))
            )
            .overlay(
                RoundedRectangle(cornerRadius: NudgeMetrics.controlRadius, style: .continuous)
                    .strokeBorder(palette.primary.opacity(0.4), lineWidth: 1)
            )

        case .downloading(let release, let progress, _, _):
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Downloading \(release.displayVersion)…")
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundStyle(palette.foreground)
                    Spacer()
                    Text("\(Int(round(progress * 100)))%")
                        .nudgeMetricFont(size: 11, weight: .bold)
                        .foregroundStyle(palette.primary)
                }
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(palette.muted)
                        Capsule()
                            .fill(palette.primary)
                            .frame(width: max(6, geo.size.width * CGFloat(min(1, max(0, progress)))))
                    }
                }
                .frame(height: 5)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(
                RoundedRectangle(cornerRadius: NudgeMetrics.controlRadius, style: .continuous)
                    .fill(palette.muted.opacity(0.65))
            )

        case .verifying(let release), .installing(let release), .readyToRelaunch(let release):
            HStack(spacing: 8) {
                ProgressView()
                    .controlSize(.small)
                    .scaleEffect(0.75)
                Text("Installing Nudge \(release.displayVersion)…")
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(palette.foreground)
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(
                RoundedRectangle(cornerRadius: NudgeMetrics.controlRadius, style: .continuous)
                    .fill(palette.muted.opacity(0.65))
            )

        case .downloadedInstaller(let release, let fileURL):
            HStack(spacing: 8) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(palette.statusPositive)
                Text("\(release.displayVersion) downloaded")
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(palette.foreground)
                Spacer()
                Button {
                    NSWorkspace.shared.activateFileViewerSelecting([fileURL])
                } label: {
                    Text("Reveal")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(palette.primaryForeground)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(palette.primary))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(
                RoundedRectangle(cornerRadius: NudgeMetrics.controlRadius, style: .continuous)
                    .fill(palette.muted.opacity(0.65))
            )

        default:
            EmptyView()
        }
    }
}
