import SwiftUI

/// Claude's service status: one line, with details to expand when a tracked service
/// has an issue.
struct StatusSection: View {
    @ObservedObject var status: StatusStore
    @State private var showingDetails = false

    var body: some View {
        let effective = status.effectiveIndicator
        let incidents = status.filteredIncidents
        let affected = status.affectedComponents
        let hasIssue = effective != "none" && (!incidents.isEmpty || !affected.isEmpty)

        VStack(alignment: .leading, spacing: 8) {
            // Compact header row
            HStack(alignment: .top, spacing: 6) {
                Circle()
                    .fill(Self.indicatorColor(effective))
                    .frame(width: 8, height: 8)
                    .padding(.top, 4)
                VStack(alignment: .leading, spacing: 2) {
                    Text(effective == "none" ? "All Claude services operational" : status.statusDescription)
                        .font(.caption)
                        .foregroundColor(Color.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(contextLine)
                        .font(.system(size: 10))
                        .foregroundColor(Color.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                if hasIssue {
                    Button(action: { showingDetails.toggle() }) {
                        HStack(spacing: 2) {
                            Text(showingDetails ? "Hide" : "Details")
                            Image(systemName: showingDetails ? "chevron.up" : "chevron.down")
                                .font(.system(size: 8))
                        }
                        .font(.caption2)
                    }
                    .buttonStyle(.borderless)
                }
            }

            if hasIssue && showingDetails {
                details(incidents: incidents, affected: affected)
            }
        }
    }

    private func details(incidents: [StatusIncident], affected: [StatusComponent]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(incidents) { incident in
                VStack(alignment: .leading, spacing: 6) {
                    Text(incident.name)
                        .font(.system(size: 12, weight: .semibold))
                        .fixedSize(horizontal: false, vertical: true)

                    // Status badge and when it was updated
                    HStack(spacing: 8) {
                        Text(incident.status.uppercased())
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Self.badgeColor(incident.status))
                            .cornerRadius(3)
                        if let updated = incident.updatedAt {
                            Text("Updated \(Format.relative(updated))")
                                .font(.caption2)
                                .foregroundColor(Color.secondaryText)
                        }
                    }

                    if !incident.latestUpdate.isEmpty {
                        Text(incident.latestUpdate)
                            .font(.caption)
                            .foregroundColor(.primary)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.top, 2)
                    }
                }
            }

            // Affected services, when there's no formal incident
            if incidents.isEmpty && !affected.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Affected services")
                        .font(.caption2)
                        .fontWeight(.semibold)
                        .foregroundColor(Color.secondaryText)
                    ForEach(affected) { component in
                        HStack(spacing: 6) {
                            Circle()
                                .fill(Color.orange)
                                .frame(width: 5, height: 5)
                            Text(component.name).font(.caption2)
                            Spacer()
                            Text(Self.label(forComponentStatus: component.status))
                                .font(.caption2)
                                .foregroundColor(Color.secondaryText)
                        }
                    }
                }
            }

            Divider()

            HStack {
                if let lastCheck = status.lastUpdated {
                    Text("Checked \(Format.relative(lastCheck))")
                        .font(.caption2)
                        .foregroundColor(Color.secondaryText)
                }
                Spacer()
                Button(action: { NSWorkspace.shared.open(AppInfo.statusPageURL) }) {
                    Text("Open status page →")
                        .font(.caption2)
                }
                .buttonStyle(.borderless)
            }
        }
        .padding(10)
        .background(Color.orange.opacity(0.10))
        .cornerRadius(6)
    }

    /// "Tracks claude.ai, Claude Console, … · checked just now", or what's affected.
    private var contextLine: String {
        let tracked = status.trackedComponents
        let trackedNames = tracked.prefix(4).map { Self.shortName($0.name) }.joined(separator: ", ")
        let more = tracked.count > 4 ? " +\(tracked.count - 4)" : ""
        let trackedSummary = tracked.isEmpty ? "No services tracked" : "Tracks \(trackedNames)\(more)"

        if status.effectiveIndicator == "none" {
            guard let lastCheck = status.lastUpdated else { return trackedSummary }
            return "\(trackedSummary) · checked \(Format.relative(lastCheck))"
        }
        let affected = status.affectedComponents
        if !affected.isEmpty {
            let names = affected.prefix(3).map { Self.shortName($0.name) }.joined(separator: ", ")
            let others = affected.count > 3 ? " +\(affected.count - 3)" : ""
            return "Affects: \(names)\(others)"
        }
        guard let lastCheck = status.lastUpdated else { return "" }
        return "Checked \(Format.relative(lastCheck))"
    }

    /// "Claude Console (platform.claude.com)" → "Claude Console".
    private static func shortName(_ name: String) -> String {
        guard let paren = name.range(of: " (") else { return name }
        return String(name[..<paren.lowerBound])
    }

    private static func indicatorColor(_ indicator: String) -> Color {
        switch indicator {
        case "none": return .green
        case "minor": return .yellow
        case "major": return .orange
        case "critical": return .red
        default: return .gray
        }
    }

    private static func badgeColor(_ status: String) -> Color {
        switch status {
        case "investigating": return Color.red.opacity(0.8)
        case "identified": return Color.orange
        case "monitoring": return Color.blue
        case "resolved": return Color.green
        default: return Color.gray
        }
    }

    private static func label(forComponentStatus status: String) -> String {
        switch status {
        case "degraded_performance": return "degraded"
        case "partial_outage": return "partial outage"
        case "major_outage": return "major outage"
        case "under_maintenance": return "maintenance"
        default: return status
        }
    }
}
