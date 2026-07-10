import SwiftUI

struct CustodyTimelineView: View {
    let document: VaultDocument
    @EnvironmentObject var authManager: AuthenticationManager

    private var events: [CustodyEvent] {
        CustodyService.shared.events(for: document, isAdmin: authManager.isAdmin)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Chain of Custody")
                    .font(.headline)
                Spacer()
                if authManager.isAdmin {
                    Label("Admin view", systemImage: "shield.lefthalf.filled")
                        .font(.caption2)
                        .foregroundColor(.accentColor)
                }
            }
            .padding(.horizontal)
            .padding(.top, 8)
            .padding(.bottom, 12)

            if events.isEmpty {
                Text("No custody events recorded yet.")
                    .font(.subheadline).foregroundColor(.secondary).padding()
            } else {
                ForEach(Array(events.enumerated()), id: \.element.id) { index, event in
                    timelineRow(event: event, isLast: index == events.count - 1)
                }
            }

            // Integrity footer
            if let hash = document.contentHash {
                Divider().padding(.vertical, 8)
                HStack(spacing: 6) {
                    Image(systemName: "lock.shield").foregroundColor(.green).font(.caption)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Content integrity verified")
                            .font(.caption2.weight(.semibold)).foregroundColor(.green)
                        Text("SHA-256: \(hash.prefix(24))…")
                            .font(.caption2).foregroundColor(.secondary)
                    }
                }
                .padding(.horizontal)
                .padding(.bottom, 16)
            }
        }
    }

    private func timelineRow(event: CustodyEvent, isLast: Bool) -> some View {
        HStack(alignment: .top, spacing: 12) {
            // Timeline track
            VStack(spacing: 0) {
                ZStack {
                    Circle()
                        .fill(iconColor(for: event.action).opacity(0.15))
                        .frame(width: 32, height: 32)
                    Image(systemName: event.action.systemImage)
                        .font(.caption)
                        .foregroundColor(iconColor(for: event.action))
                }
                if !isLast {
                    Rectangle()
                        .fill(Color(.systemGray4))
                        .frame(width: 1)
                        .frame(maxHeight: .infinity)
                }
            }
            .frame(width: 32)

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(event.action.displayName)
                        .font(.subheadline.weight(.medium))
                    if event.visibility == .adminOnly {
                        Image(systemName: "eye.slash")
                            .font(.caption2).foregroundColor(.secondary)
                    }
                    Spacer()
                    Text(event.timestamp, style: .relative)
                        .font(.caption2).foregroundColor(.secondary)
                }

                if let email = event.actorEmail {
                    Text(email).font(.caption).foregroundColor(.secondary)
                } else {
                    Text(event.actor).font(.caption).foregroundColor(.secondary)
                }

                if let notes = event.notes {
                    Text(notes).font(.caption).foregroundColor(.secondary)
                }

                if authManager.isAdmin {
                    if let deviceId = event.deviceId {
                        Text("Device: \(deviceId.prefix(12))…")
                            .font(.caption2).foregroundColor(Color(.tertiaryLabel))
                    }
                    if let ip = event.ipAddress {
                        Text("IP: \(ip)").font(.caption2).foregroundColor(Color(.tertiaryLabel))
                    }
                }
            }
            .padding(.bottom, isLast ? 0 : 16)
        }
        .padding(.horizontal)
    }

    private func iconColor(for action: CustodyAction) -> Color {
        switch action {
        case .ingested, .emailCaptured, .scanned, .uploaded: return .blue
        case .viewed, .downloaded:                           return .gray
        case .annotated:                                     return .purple
        case .statusChanged, .versionBumped:                 return .orange
        case .accessDenied:                                  return .red
        case .permissionGranted:                             return .green
        case .permissionRevoked:                             return .red
        default:                                             return .secondary
        }
    }
}
