import SwiftUI

/// The label of a tracked bar with its direction symbol: a cap for limits, a flag (or ✓) for
/// targets, a scope for ranges, an equals sign for steady.
struct TrackLabel: View {
    let text: String
    let track: TrackStyle?

    var body: some View {
        HStack(spacing: 3) {
            if let track {
                Image(systemName: track.symbol)
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(track.tone == .toGo ? Color.secondary : track.tone.color)
                    .accessibilityHidden(true)
            }
            Text(text)
                .font(.system(.caption, design: .rounded, weight: .semibold))
                .foregroundStyle(.primary)
        }
    }
}

enum TrackStatusColor {
    static func color(_ track: TrackStyle) -> Color {
        switch track.tone {
        case .toGo: .secondary
        case .good, .great, .caution, .bad: track.tone.color
        }
    }
}

/// A short line across a vertical bar where the user usually is by now.
struct TrackPaceTick: View {
    let fraction: Double
    let barHeight: CGFloat
    let barWidth: CGFloat

    var body: some View {
        Capsule()
            .fill(Color.primary.opacity(0.55))
            .frame(width: barWidth + 8, height: 2)
            .offset(y: -min(max(barHeight * fraction - 1, 0), barHeight - 2))
            .accessibilityLabel("Your usual amount by now")
    }
}

/// A horizontal tracked row: label with direction symbol, value and goal, a bar in the track's
/// tone with a pace tick, and the status line. Used by the health cards.
struct TrackedProgressRow: View {
    let label: String
    let current: Double
    let goal: Int
    let unit: String
    let track: TrackStyle

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                HStack(spacing: 5) {
                    Image(systemName: track.symbol)
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(track.tone == .toGo ? Color.secondary : track.tone.color)
                        .accessibilityHidden(true)
                    Text(label)
                        .font(.system(.subheadline, design: .rounded, weight: .medium))
                }
                Spacer()
                Text(goal > 0 ? "\(MacroValueFormatter.string(current))\(unit) / \(goal)\(unit)" : "\(MacroValueFormatter.string(current))\(unit)")
                    .font(.system(.subheadline, design: .rounded))
                    .foregroundStyle(.secondary)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(track.tone.color.opacity(0.12))
                    Capsule()
                        .fill(LinearGradient(colors: track.tone.gradient, startPoint: .leading, endPoint: .trailing))
                        .frame(width: max(6, geo.size.width * TrackStyle.progress(current: current, goal: Double(goal))))
                    if let pace = track.paceFraction {
                        Capsule()
                            .fill(Color.primary.opacity(0.55))
                            .frame(width: 2, height: 14)
                            .offset(x: min(max(geo.size.width * pace - 1, 0), geo.size.width - 2))
                            .accessibilityLabel("Your usual amount by now")
                    }
                }
            }
            .frame(height: 8)
            HStack(spacing: 6) {
                Text(track.status)
                    .foregroundStyle(TrackStatusColor.color(track))
                if let note = track.paceNote {
                    Text("· \(note)")
                        .foregroundStyle(TrackTone.caution.color)
                }
            }
            .font(.system(.caption2, design: .rounded, weight: .medium))
        }
        .accessibilityElement(children: .combine)
    }
}
