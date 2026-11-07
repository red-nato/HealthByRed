import SwiftUI
import UIKit

/// Template artwork is drawn once. iOS owns tab sizing, selection and glass.
@MainActor
enum HealthRingSymbol {
    static let image: UIImage = {
        let image = UIGraphicsImageRenderer(size: CGSize(width: 25, height: 25)).image { _ in
            UIColor.label.setStroke()
            let outer = UIBezierPath(ovalIn: CGRect(x: 2, y: 2, width: 21, height: 21))
            outer.lineWidth = 1.6
            outer.stroke()
            let inner = UIBezierPath(ovalIn: CGRect(x: 4.4, y: 4.4, width: 16.2, height: 16.2))
            inner.lineWidth = 1.1
            inner.stroke()
            UIColor.label.setFill()
            // Circular caps, not narrow radial peaks: all three sensors stay round.
            for angle in [Double.pi / 4, .pi / 2, 3 * .pi / 4] {
                let center = CGPoint(x: 12.5 + 8 * cos(angle), y: 12.5 + 8 * sin(angle))
                UIBezierPath(ovalIn: CGRect(x: center.x - 1.65, y: center.y - 1.65,
                                           width: 3.3, height: 3.3)).fill()
            }
        }
        return image.withRenderingMode(.alwaysTemplate)
    }()
}

struct HealthRingGlyph: View {
    var body: some View {
        Image(uiImage: HealthRingSymbol.image).renderingMode(.template)
            .accessibilityHidden(true)
    }
}

struct HealthBrandTitle: View {
    var compact = false
    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: compact ? 5 : 7) {
            HealthRingGlyph().foregroundStyle(LinearGradient(colors: compact ? [Obs.homeAccent, Obs.accent] : [Obs.homeAccent, Obs.homeAccent], startPoint: .topLeading, endPoint: .bottomTrailing))
                .scaleEffect(compact ? 0.68 : 0.9)
                .frame(width: compact ? 18 : 25)
                .alignmentGuide(.firstTextBaseline) { $0[VerticalAlignment.center] + 7 }
            Text("Health").font(.system(size: compact ? 18 : 24, weight: .semibold))
                .tracking(-0.7).foregroundStyle(Obs.ink)
            HStack(spacing: 0) {
                Text("by Red").foregroundStyle(Obs.ink2)
                Text(".").foregroundStyle(Obs.brandRed)
            }.font(.system(size: compact ? 10 : 12, weight: .medium))
        }
        .fixedSize(horizontal: true, vertical: false)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Health by Red")
    }
}

struct HealthSettingsBackdrop: View {
    var body: some View {
        ZStack {
            Obs.paper
            RadialGradient(colors: [Obs.homeAccent.opacity(0.08), .clear], center: .topLeading,
                           startRadius: 0, endRadius: 300)
            RadialGradient(colors: [Obs.accent.opacity(0.07), .clear], center: .bottomTrailing,
                           startRadius: 0, endRadius: 320)
        }.ignoresSafeArea().accessibilityHidden(true)
    }
}

/// Retain the BLE controller without subscribing the entire dashboard to every
/// progress message. Individual controls observe RingSync; Root observes busy only.
@MainActor
final class HealthRingOwner: ObservableObject {
    let ring = RingSync()
}

struct HealthNativeTabBehavior: ViewModifier {
    @ViewBuilder func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content.tabBarMinimizeBehavior(.onScrollDown)
        } else {
            content
        }
    }
}

struct HealthSettingsView: View {
    @Binding var appearance: String
    let onProfile: () -> Void
    let onRing: () -> Void
    let onModules: () -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(spacing: 0) {
                        VStack(alignment: .leading, spacing: 9) {
                            Text("YOUR SPACE").font(.caption2.weight(.semibold)).tracking(1.6)
                                .foregroundStyle(Obs.brandBlend)
                            Text("Make it yours.").font(.title2.weight(.medium)).foregroundStyle(Obs.ink)
                            Text("A little balance.\nYour own rhythm.")
                                .font(.subheadline).foregroundStyle(Obs.ink2)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        HealthRingPlacement(section: 2, size: 154)
                    }
                    .padding(.vertical, 6)
                    .accessibilityElement(children: .combine)
                }
                .listRowBackground(Color.clear).listRowInsets(EdgeInsets())

                Section("Personal") {
                    Button(action: onProfile) {
                        settingsLabel("Profile & Apple Health", symbol: "person.crop.circle")
                    }
                }
                .listRowBackground(Obs.surface)

                Section("Application") {
                    Picker("Appearance", selection: $appearance) {
                        Text("System").tag("system")
                        Text("Light").tag("light")
                        Text("Dark").tag("dark")
                    }
                    .accessibilityIdentifier("health-appearance")
                    Button(action: onModules) {
                        settingsLabel("Modules", symbol: "square.stack.3d.up")
                    }
                }
                .listRowBackground(Obs.surface)

                Section("Device") {
                    Button(action: onRing) {
                        Label { Text("Ring settings").foregroundStyle(Obs.ink) } icon: { HealthRingGlyph().foregroundStyle(Obs.brandBlend) }
                    }
                }
                .listRowBackground(Obs.surface)

                Section {
                    DisclosureGroup {
                        Text("The ring connects over Bluetooth and processes data on this device. Apple Health is authorized separately.")
                        Text("Exports use the system share sheet. Your iOS backup settings also apply to local app data.")
                    } label: {
                        settingsLabel("Privacy & connections", symbol: "hand.raised")
                    }
                } footer: {
                    HealthBrandTitle(compact: true).padding(.top, 12)
                }
                .listRowBackground(Obs.surface)
            }
            .scrollContentBackground(.hidden)
            .background { HealthSettingsBackdrop() }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.large)
        }
        .tint(Obs.settingsAccent)
    }
    private func settingsLabel(_ title: String, symbol: String) -> some View {
        Label { Text(title).foregroundStyle(Obs.ink) } icon: {
            Image(systemName: symbol).foregroundStyle(Obs.brandBlend)
        }
    }
}

struct HealthRingHub: View {
    let device: Device?
    @ObservedObject var ring: RingSync
    @ObservedObject var modules: ModuleStore
    let onConnect: () -> Void
    let onModules: () -> Void

    private var syncStamp: String {
        if let date = ring.lastSuccessfulSyncAt {
            return date.formatted(.dateTime.day().month(.abbreviated).hour().minute().locale(Locale(identifier: "en_US")))
        }
        let stamp = [device?.synced, device?.synced_hm].compactMap { $0 }.joined(separator: " · ")
        return stamp.isEmpty ? "Not synced yet" : stamp
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    VStack(spacing: 6) {
                        HealthRingPlacement(section: 1, size: 218)
                        Text("Product image · not a live reading")
                            .font(.caption2).foregroundStyle(Obs.muted)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
                }
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())

                Section {
                    LabeledContent("Last battery level", value: device?.battery_pct.map { "\($0)%" } ?? "—")
                    LabeledContent("Last synced", value: syncStamp)
                }
                .listRowBackground(Obs.surface)

                Section {
                    Toggle("Oura connector", isOn: $modules.ouraEnabled)
                    Button(action: onConnect) {
                        HStack {
                            if ring.busy { ProgressView().controlSize(.small) }
                            Text(ring.busy ? "View sync" : "Connect & sync")
                            Spacer()
                            Image(systemName: "arrow.triangle.2.circlepath")
                        }
                    }
                    .disabled(!modules.ouraEnabled)
                    if let issue = ring.connectionIssue {
                        Label(issue, systemImage: "exclamationmark.circle")
                            .font(.footnote).foregroundStyle(Obs.bad)
                    }
                } footer: {
                    Text(modules.ouraEnabled ? "Direct Bluetooth connection. Your data stays on this device." : "Enable the connector to pair your ring. Your saved history remains available.")
                }
                .listRowBackground(Obs.surface)

                Section {
                    DisclosureGroup("Device information") {
                        LabeledContent("Serial number", value: device?.serial ?? ring.knownSerial ?? "—")
                        LabeledContent("Firmware", value: device?.firmware ?? "—")
                        LabeledContent("History", value: device?.days_of_data.map { String(format: "%.0f days", $0) } ?? "—")
                    }
                    Button(action: onModules) {
                        Label("Manage modules", systemImage: "square.stack.3d.up")
                    }
                }
                .listRowBackground(Obs.surface)
            }
            .scrollContentBackground(.hidden)
            .background(Obs.paper)
            .navigationTitle("Oura Ring")
            .navigationBarTitleDisplayMode(.large)
        }
        .tint(Obs.accent)
    }
}
