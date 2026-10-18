import AppKit

import SwiftUI

struct FloatingIslandView: View {

    @ObservedObject var presentation: IslandPresentationModel

    let onSizeChange: (CGSize) -> Void

    @StateObject private var musicService = MusicService()

    @StateObject private var safariService = SafariDownloadService()

    @StateObject private var batteryService = BatteryService()

    @StateObject private var appStoreService = AppStoreDownloadService()

    @State private var chargeSamplePercentage: Int?

    @State private var chargeSampleDate: Date?

    @State private var chargingRatePercentPerMinute: Double?

    private let idleWidth: CGFloat = 240

    private let compactWidth: CGFloat = 280

    private let expandedWidth: CGFloat = 320

    private let compactHeight: CGFloat = 40

    private let expandedHeight: CGFloat = 200

    private let expansionAnimation = Animation.spring(
        response: 0.62,
        dampingFraction: 0.58,
        blendDuration: 0.05
    )

    private enum Feature: Equatable {

        case idle

        case safari

        case music

        case appStore

        case battery

    }

    private var activeFeature: Feature {

        if safariService.download != nil {

            return .safari

        }

        if musicService.isPlaying {

            return .music

        }

        if appStoreService.isRunning {

            return .appStore

        }

        if batteryService.isAvailable &&

            (batteryService.percentage < 20 || batteryService.isCharging) {

            return .battery

        }

        return .idle

    }

    private var panelWidth: CGFloat {

        if case .idle = activeFeature {

            return idleWidth

        }

        return presentation.isExpanded && activeFeature != .battery
            ? expandedWidth
            : compactWidth

    }

    private var panelHeight: CGFloat {

        if case .idle = activeFeature {

            return compactHeight

        }

        return presentation.isExpanded && activeFeature != .battery
            ? expandedHeight
            : compactHeight

    }

    private var musicProgress: CGFloat {

        guard musicService.duration.isFinite,

              musicService.duration > 0,

              musicService.currentTime.isFinite else {

            return 0

        }

        return CGFloat(

            min(max(musicService.currentTime / musicService.duration, 0), 1)

        )

    }

    // MARK: - Main view

    var body: some View {

        ZStack(alignment: .top) {
            ZStack(alignment: .top) {
                if presentation.isExpanded &&
                    isFeatureActive && activeFeature != .battery {
                    expandedContent
                        .frame(width: expandedWidth, height: expandedHeight, alignment: .top)
                        .transition(
                            .asymmetric(
                                insertion: .opacity.combined(
                                    with: .scale(scale: 0.94, anchor: .top)
                                ),
                                removal: .opacity.combined(
                                    with: .scale(scale: 0.98, anchor: .top)
                                )
                            )
                        )
                        .zIndex(1)
                } else {
                    compactContent
                        .frame(width: panelWidth, height: compactHeight, alignment: .top)
                        .transition(.opacity)
                        .zIndex(0)
                }
            }
            .frame(width: expandedWidth, height: expandedHeight, alignment: .top)
            .frame(width: panelWidth, height: panelHeight, alignment: .top)
            .background(Color.black)
            .clipShape(islandShape)
            .contentShape(islandShape)
            .animation(expansionAnimation, value: presentation.isExpanded)
            .animation(expansionAnimation, value: activeFeature)
            .onTapGesture {
                guard isFeatureActive, activeFeature != .battery else { return }
                toggleExpansion()
            }
        }

        // Keep the hosting area fixed so the top edge does not move.

        .frame(width: 320, height: 200, alignment: .top)

        .background(Color.clear)

        .onAppear {

            musicService.startPolling()

            safariService.startPolling()

            batteryService.startPolling()
            if batteryService.isCharging {
                chargeSamplePercentage = batteryService.percentage
                chargeSampleDate = Date()
            }

            appStoreService.startPolling()

            Task { @MainActor in
                await musicService.refresh()
                publishSize()
            }

        }

        .onDisappear {

            musicService.stopPolling()

            safariService.stopPolling()

            batteryService.stopPolling()

            appStoreService.stopPolling()

        }

        .onChange(of: presentation.isExpanded) { _, _ in

            publishSize()

        }

        // Feature activation changes the displayed content, but does not
        // automatically expand the island. Only a click on the island expands it.
        .onChange(of: isFeatureActive) { _, active in
            if !active {
                withAnimation(expansionAnimation) {
                    presentation.isExpanded = false
                }
            }
            publishSize()
        }
        .onChange(of: activeFeature) { _, feature in
            if feature == .battery || feature == .idle {
                withAnimation(expansionAnimation) {
                    presentation.isExpanded = false
                }
            }
            publishSize()
        }
        .onChange(of: batteryService.percentage) { _, newPercentage in
            updateChargingEstimate(percentage: newPercentage)
            if !isFeatureActive { collapseIfIdle() }
            publishSize()
        }
        .onChange(of: batteryService.isCharging) { _, charging in
            if charging {
                chargeSamplePercentage = batteryService.percentage
                chargeSampleDate = Date()
                chargingRatePercentPerMinute = nil
            } else {
                chargeSamplePercentage = nil
                chargeSampleDate = nil
                chargingRatePercentPerMinute = nil
            }
            if activeFeature == .battery {
                withAnimation(expansionAnimation) {
                    presentation.isExpanded = false
                }
            }
            publishSize()
        }
        .onChange(of: batteryService.isPluggedIn) { _, _ in
            if !isFeatureActive { collapseIfIdle() }
            publishSize()
        }
        .onChange(of: appStoreService.isRunning) { _, _ in
            if !isFeatureActive { collapseIfIdle() }
            publishSize()
        }

    }

    private var isFeatureActive: Bool {

        if case .idle = activeFeature {

            return false

        }

        return true

    }

    private var islandShape: UnevenRoundedRectangle {
        UnevenRoundedRectangle(
            topLeadingRadius: 0,
            bottomLeadingRadius: presentation.isExpanded && activeFeature != .battery ? 30 : 18,
            bottomTrailingRadius: presentation.isExpanded && activeFeature != .battery ? 30 : 18,
            topTrailingRadius: 0,
            style: .continuous
        )
    }

    private func publishSize() {

        onSizeChange(

            CGSize(width: panelWidth, height: panelHeight)

        )

    }

    private func collapseIfIdle() {

        if !isFeatureActive {

            withAnimation(expansionAnimation) {

                presentation.isExpanded = false

            }

        }

    }

    // MARK: - Compact content

    @ViewBuilder

    private var compactContent: some View {

        switch activeFeature {

        case .idle:

            idleContent

        case .safari:

            safariCompactContent

        case .music:

            musicCompactContent

        case .appStore:

            appStoreCompactContent

        case .battery:

            batteryCompactContent

        }

    }

    private var idleContent: some View {

        Color.black

            .frame(width: idleWidth, height: compactHeight)

    }

    private var musicCompactContent: some View {

        HStack(spacing: 9) {

            albumArtwork

                .frame(width: 28, height: 28)

                .clipShape(RoundedRectangle(cornerRadius: 6))

            VStack(alignment: .leading, spacing: 2) {

                Text(musicService.title.isEmpty

                     ? "Apple Music"

                     : musicService.title)

                    .font(.system(size: 10, weight: .semibold))

                    .foregroundStyle(.white)

                    .lineLimit(1)

                Text(musicService.artist.isEmpty

                     ? "Not Playing"

                     : musicService.artist)

                    .font(.system(size: 9))

                    .foregroundStyle(.white.opacity(0.65))

                    .lineLimit(1)

            }

            Spacer(minLength: 4)

            compactWaveform

                .frame(width: 24, height: 24)

        }

        .padding(.horizontal, 10)

        .frame(width: compactWidth, height: compactHeight)

        .background(Color.black)

    }

    private var safariCompactContent: some View {

        HStack(spacing: 9) {

            Image(systemName: "safari.fill")

                .font(.system(size: 21))

                .foregroundStyle(.white)

                .frame(width: 28, height: 28)

            VStack(alignment: .leading, spacing: 2) {

                Text("Safari Download")

                    .font(.system(size: 10, weight: .semibold))

                    .foregroundStyle(.white)

                Text(safariService.download?.fileName ?? "Checking…")

                    .font(.system(size: 9))

                    .foregroundStyle(.white.opacity(0.65))

                    .lineLimit(1)

            }

            Spacer(minLength: 4)

            if let progress = safariService.download?.progress {

                Text("\(Int(progress * 100))%")

                    .font(.system(size: 11, weight: .medium))

                    .foregroundStyle(.white)

            } else {

                ProgressView()

                    .controlSize(.small)

                    .tint(.white)

            }

        }

        .padding(.horizontal, 10)

        .frame(width: compactWidth, height: compactHeight)

        .background(Color.black)

    }

    private var appStoreCompactContent: some View {

        HStack(spacing: 9) {

            Image(systemName: "appstore.fill")

                .font(.system(size: 24))

                .foregroundStyle(.white)

                .frame(width: 28, height: 28)

            VStack(alignment: .leading, spacing: 2) {

                Text("App Store")

                    .font(.system(size: 10, weight: .semibold))

                    .foregroundStyle(.white)

                Text("App Store is open")

                    .font(.system(size: 9))

                    .foregroundStyle(.white.opacity(0.65))

            }

            Spacer()

            Image(systemName: "arrow.down.circle")

                .font(.system(size: 17))

                .foregroundStyle(.white.opacity(0.8))

        }

        .padding(.horizontal, 10)

        .frame(width: compactWidth, height: compactHeight)

        .background(Color.black)

    }

    private var batteryCompactContent: some View {
        HStack(spacing: 9) {
            Image(systemName: batteryIcon)
                .font(.system(size: 18))
                .foregroundStyle(batteryColor)
                .frame(width: 26, height: 26)

            VStack(alignment: .leading, spacing: 2) {
                Text(batteryService.isCharging ? "Charging" : "Low Battery")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.white)

                Text(batteryService.isCharging
                     ? "Until 80%"
                     : "Battery level")
                    .font(.system(size: 9))
                    .foregroundStyle(.white.opacity(0.65))
            }

            Spacer(minLength: 4)

            if batteryService.isCharging {
                Text(estimatedTimeTo80)
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(.green)
                    .lineLimit(1)
            } else {
                Text("\(batteryService.percentage)%")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(batteryService.percentage < 20 ? .red : .white)
            }
        }
        .padding(.horizontal, 10)
        .frame(width: compactWidth, height: compactHeight)
        .background(Color.black)
    }

    // MARK: - Expanded content

    @ViewBuilder

    private var expandedContent: some View {

        switch activeFeature {

        case .idle:

            idleContent

        case .safari:

            safariExpandedContent

        case .music:

            musicExpandedContent

        case .appStore:

            appStoreExpandedContent

        case .battery:

            batteryCompactContent

        }

    }

    private var musicExpandedContent: some View {

        VStack(spacing: 0) {

            Color.clear.frame(height: 48)

            HStack(spacing: 10) {

                albumArtwork

                    .frame(width: 56, height: 56)

                    .clipShape(RoundedRectangle(cornerRadius: 8))

                VStack(alignment: .leading, spacing: 4) {

                    Text(musicService.isPlaying

                         ? "NOW PLAYING"

                         : "APPLE MUSIC")

                        .font(.system(size: 9, weight: .medium))

                        .foregroundStyle(.gray)

                    Text(musicService.title.isEmpty

                         ? "No music playing"

                         : musicService.title)

                        .font(.system(size: 13, weight: .semibold))

                        .foregroundStyle(.white)

                        .lineLimit(1)

                    Text(musicService.artist.isEmpty

                         ? "Open Apple Music to begin"

                         : musicService.artist)

                        .font(.system(size: 11))

                        .foregroundStyle(.gray)

                        .lineLimit(1)

                }

                Spacer(minLength: 0)

            }

            VStack(spacing: 4) {

                GeometryReader { geometry in

                    ZStack(alignment: .leading) {

                        Capsule().fill(Color.white.opacity(0.2))

                        Capsule()

                            .fill(Color.white)

                            .frame(

                                width: geometry.size.width * musicProgress

                            )

                    }

                }

                .frame(height: 3)

                HStack {

                    Text(formatTime(musicService.currentTime))

                    Spacer()

                    Text(formatTime(musicService.duration))

                }

                .font(.system(size: 9, design: .monospaced))

                .foregroundStyle(.gray)

            }

            .padding(.top, 8)

            HStack {

                Text("Apple Music")

                Spacer()

                Text("Playing")

            }

            .font(.system(size: 10))

            .foregroundStyle(.gray)

            .padding(.top, 7)

            HStack {

                Button {

                    Task { await musicService.previousTrack() }

                } label: {

                    Image(systemName: "backward.end.fill")

                }

                .buttonStyle(.plain)

                Spacer()

                Button {

                    Task { await musicService.playPause() }

                } label: {

                    Image(systemName: "pause.fill")

                }

                .buttonStyle(.plain)

                Spacer()

                Button {

                    Task { await musicService.nextTrack() }

                } label: {

                    Image(systemName: "forward.end.fill")

                }

                .buttonStyle(.plain)

            }

            .font(.system(size: 17))

            .foregroundStyle(.white)

            .padding(.horizontal, 25)

            .padding(.top, 7)

            Spacer(minLength: 0)

        }

        .padding(.horizontal, 16)

        .frame(width: expandedWidth, height: expandedHeight)

        .background(Color.black)

    }

    private var safariExpandedContent: some View {

        VStack(alignment: .leading, spacing: 12) {

            Color.clear.frame(height: 38)

            HStack(spacing: 10) {

                Image(systemName: "safari.fill")

                    .font(.system(size: 27))

                    .foregroundStyle(.white)

                VStack(alignment: .leading, spacing: 3) {

                    Text("SAFARI DOWNLOAD")

                        .font(.system(size: 9, weight: .medium))

                        .foregroundStyle(.gray)

                    Text(safariService.download?.fileName

                         ?? "No active download")

                        .font(.system(size: 12, weight: .semibold))

                        .foregroundStyle(.white)

                        .lineLimit(2)

                }

                Spacer(minLength: 0)

            }

            if let download = safariService.download {

                if let progress = download.progress {

                    HStack {

                        Text("\(Int(progress * 100))%")

                        Spacer()

                        Text(

                            "\(formatBytes(download.bytesDownloaded)) of " +

                            "\(formatBytes(download.totalBytes ?? 0))"

                        )

                    }

                    .font(.system(size: 10, weight: .medium))

                    .foregroundStyle(.white.opacity(0.8))

                    ProgressView(value: progress)

                        .tint(.white)

                } else {

                    ProgressView()

                        .progressViewStyle(.linear)

                        .tint(.white)

                    Text(

                        "\(formatBytes(download.bytesDownloaded)) downloaded"

                    )

                    .font(.system(size: 10))

                    .foregroundStyle(.gray)

                }

                HStack {

                    VStack(alignment: .leading, spacing: 4) {

                        Text("SPEED")

                            .font(.system(size: 8, weight: .medium))

                            .foregroundStyle(.gray)

                        Text(

                            "\(formatBytes(Int64(download.speedBytesPerSecond)))/s"

                        )

                        .font(.system(size: 11, weight: .medium))

                        .foregroundStyle(.white)

                    }

                    Spacer()

                    VStack(alignment: .trailing, spacing: 4) {

                        Text("TIME LEFT")

                            .font(.system(size: 8, weight: .medium))

                            .foregroundStyle(.gray)

                        Text(remainingTime(

                            download.estimatedSecondsRemaining

                        ))

                        .font(.system(size: 11, weight: .medium))

                        .foregroundStyle(.white)

                    }

                }

            } else {

                Text("No active Safari download")

                    .font(.system(size: 11))

                    .foregroundStyle(.gray)

            }

            Spacer(minLength: 0)

        }

        .padding(.horizontal, 16)

        .padding(.bottom, 10)

        .frame(width: expandedWidth, height: expandedHeight, alignment: .top)

        .background(Color.black)

    }

    private var appStoreExpandedContent: some View {

        VStack(alignment: .leading, spacing: 12) {

            Color.clear.frame(height: 42)

            HStack(spacing: 10) {

                Image(systemName: "appstore.fill")

                    .font(.system(size: 34))

                    .foregroundStyle(.white)

                VStack(alignment: .leading, spacing: 4) {

                    Text("MAC APP STORE")

                        .font(.system(size: 9, weight: .medium))

                        .foregroundStyle(.gray)

                    Text("App Store is open")

                        .font(.system(size: 13, weight: .semibold))

                        .foregroundStyle(.white)

                }

                Spacer()

            }

            Divider().overlay(Color.white.opacity(0.2))

            Text(

                "Download progress and speed aren't available " +

                "through this monitor."

            )

            .font(.system(size: 11))

            .foregroundStyle(.gray)

            .fixedSize(horizontal: false, vertical: true)

            Button {

                appStoreService.openAppStore()

            } label: {

                Label("Open App Store", systemImage: "arrow.up.right.square")

                    .font(.system(size: 11, weight: .medium))

                    .foregroundStyle(.white)

                    .frame(maxWidth: .infinity)

                    .padding(.vertical, 7)

                    .background(Color.white.opacity(0.12))

                    .clipShape(RoundedRectangle(cornerRadius: 8))

            }

            .buttonStyle(.plain)

            Spacer(minLength: 0)

        }

        .padding(.horizontal, 16)

        .padding(.bottom, 10)

        .frame(width: expandedWidth, height: expandedHeight, alignment: .top)

        .background(Color.black)

    }

    private var batteryExpandedContent: some View {

        VStack(alignment: .leading, spacing: 12) {

            Color.clear.frame(height: 42)

            HStack(spacing: 12) {

                Image(systemName: batteryIcon)

                    .font(.system(size: 35))

                    .foregroundStyle(batteryColor)

                VStack(alignment: .leading, spacing: 4) {

                    Text("BATTERY")

                        .font(.system(size: 9, weight: .medium))

                        .foregroundStyle(.gray)

                    Text("\(batteryService.percentage)%")

                        .font(.system(size: 22, weight: .semibold))

                        .foregroundStyle(.white)

                }

                Spacer()

                if batteryService.isCharging {

                    Image(systemName: "bolt.fill")

                        .font(.system(size: 20))

                        .foregroundStyle(.green)

                }

            }

            ProgressView(

                value: Double(batteryService.percentage),

                total: 100

            )

            .tint(batteryColor)

            Text(batteryStatus)

                .font(.system(size: 11))

                .foregroundStyle(.gray)

            Spacer(minLength: 0)

        }

        .padding(.horizontal, 16)

        .padding(.bottom, 10)

        .frame(width: expandedWidth, height: expandedHeight, alignment: .top)

        .background(Color.black)

    }

    private var estimatedTimeTo80: String {
        let percentage = batteryService.percentage
        if percentage >= 80 { return "80% reached" }
        guard let rate = chargingRatePercentPerMinute, rate > 0 else {
            return "Calculating…"
        }
        let minutes = Int(ceil(Double(80 - percentage) / rate))
        if minutes < 1 { return "<1 min" }
        let hours = minutes / 60
        let remainingMinutes = minutes % 60
        if hours > 0 {
            return remainingMinutes == 0 ? "\(hours)h" : "\(hours)h \(remainingMinutes)m"
        }
        return "\(minutes)"
    }

    private func updateChargingEstimate(percentage: Int) {
        guard batteryService.isCharging else {
            chargeSamplePercentage = nil
            chargeSampleDate = nil
            chargingRatePercentPerMinute = nil
            return
        }

        let now = Date()
        if let previousPercentage = chargeSamplePercentage,
           let previousDate = chargeSampleDate {
            let elapsedMinutes = now.timeIntervalSince(previousDate) / 60
            let gainedPercentage = Double(percentage - previousPercentage)
            if elapsedMinutes >= 0.25, gainedPercentage > 0 {
                let measuredRate = gainedPercentage / elapsedMinutes
                // Ignore implausible jumps caused by battery percentage corrections.
                if measuredRate <= 10 {
                    chargingRatePercentPerMinute = measuredRate
                }
                chargeSamplePercentage = percentage
                chargeSampleDate = now
            }
        } else {
            chargeSamplePercentage = percentage
            chargeSampleDate = now
        }
    }

    private var albumArtwork: some View {

        Group {

            if let artwork = musicService.artwork {

                Image(nsImage: artwork)

                    .resizable()

                    .scaledToFill()

            } else {

                RoundedRectangle(cornerRadius: 7)

                    .fill(

                        LinearGradient(

                            colors: [.purple, .blue, .black],

                            startPoint: .topLeading,

                            endPoint: .bottomTrailing

                        )

                    )

                    .overlay {

                        Image(systemName: "music.note")

                            .font(.system(size: 18))

                            .foregroundStyle(.white)

                    }

            }

        }

        .frame(maxWidth: .infinity, maxHeight: .infinity)

        .clipped()

    }

    private var compactWaveform: some View {

        TimelineView(

            .animation(

                minimumInterval: 0.08,

                paused: !musicService.isPlaying

            )

        ) { timeline in

            let time = timeline.date.timeIntervalSinceReferenceDate

            HStack(spacing: 3) {

                ForEach(0..<5, id: \.self) { index in

                    let phase = time * 7 + Double(index) * 1.1

                    Capsule()

                        .fill(Color.white)

                        .frame(

                            width: 3,

                            height: musicService.isPlaying

                                ? CGFloat(4 + 16 * abs(sin(phase)))

                                : 4

                        )

                }

            }

            .frame(maxWidth: .infinity, maxHeight: .infinity)

        }

    }

    // MARK: - Battery display

    private var batteryIcon: String {

        if batteryService.isCharging {

            return "battery.100percent.bolt"

        }

        switch batteryService.percentage {

        case 0..<20:

            return "battery.25percent"

        case 20..<50:

            return "battery.50percent"

        case 50..<80:

            return "battery.75percent"

        default:

            return "battery.100percent"

        }

    }

    private var batteryColor: Color {

        if batteryService.isCharging {

            return .green

        }

        if batteryService.percentage < 20 {

            return .red

        }

        return .white

    }

    private var batteryStatus: String {

        guard batteryService.isAvailable else {

            return "Battery information unavailable"

        }

        if batteryService.isCharging {

            return "Charging"

        }

        if batteryService.isPluggedIn {

            return "Connected to power"

        }

        return "On battery power"

    }

    // MARK: - Formatting and animation

    private func formatTime(_ seconds: Double) -> String {

        guard seconds.isFinite, seconds >= 0 else {

            return "0:00"

        }

        let value = Int(seconds)

        return "\(value / 60):" + String(format: "%02d", value % 60)

    }

    private func formatBytes(_ bytes: Int64) -> String {

        let units = ["B", "KB", "MB", "GB", "TB"]

        var size = Double(max(0, bytes))

        var index = 0

        while size >= 1024 && index < units.count - 1 {

            size /= 1024

            index += 1

        }

        return String(format: "%.1f %@", size, units[index])

    }

    private func remainingTime(_ seconds: Double?) -> String {

        guard let seconds, seconds.isFinite, seconds >= 0 else {

            return "Calculating…"

        }

        let totalSeconds = Int(seconds)

        let hours = totalSeconds / 3600

        let minutes = (totalSeconds % 3600) / 60

        let remainingSeconds = totalSeconds % 60

        if hours > 0 {

            return "\(hours)h \(minutes)m"

        }

        if minutes > 0 {

            return "\(minutes)m \(remainingSeconds)s"

        }

        return "\(remainingSeconds)s"

    }

    private func toggleExpansion() {
        guard isFeatureActive, activeFeature != .battery else { return }

        NSHapticFeedbackManager.defaultPerformer.perform(
            .alignment,
            performanceTime: .now
        )

        withAnimation(expansionAnimation) {
            presentation.isExpanded.toggle()
        }
    }

}
