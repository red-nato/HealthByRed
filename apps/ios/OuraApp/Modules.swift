import SwiftUI
import UniformTypeIdentifiers

// A manifest describes a source; it is never executable code. Only adapters compiled
// into this app can access a device. Importing metadata does not grant permissions.
enum ModulePermission: String, Codable, CaseIterable, Identifiable {
    case bluetooth
    case healthRead = "health-read"
    case healthWrite = "health-write"
    case network
    case localStorage = "local-storage"

    var id: String { rawValue }
    var title: String {
        switch self {
        case .bluetooth: return "Bluetooth"
        case .healthRead: return "Read Apple Health"
        case .healthWrite: return "Write to Apple Health"
        case .network: return "Internet access"
        case .localStorage: return "Local storage"
        }
    }
    var symbol: String {
        switch self {
        case .bluetooth: return "antenna.radiowaves.left.and.right"
        case .healthRead: return "heart.text.square"
        case .healthWrite: return "heart.badge.plus"
        case .network: return "network"
        case .localStorage: return "internaldrive"
        }
    }
}

struct ModuleManifest: Codable, Identifiable, Equatable {
    var schemaVersion: Int
    var id: String
    var name: String
    var version: String
    var author: String
    var description: String
    var permissions: [ModulePermission]

    static let maximumBytes = 65_536
    static let ouraID = "org.openhealth.oura"
    static let exampleJSON = """
    {
      "schemaVersion": 1,
      "id": "community.example.ring",
      "name": "My device",
      "version": "1.0.0",
      "author": "Community",
      "description": "Description of the data source.",
      "permissions": ["bluetooth", "local-storage"]
    }
    """

    static func decode(_ data: Data) throws -> ModuleManifest {
        guard data.count <= maximumBytes else { throw ManifestError.invalid("The file exceeds the 64 KB limit.") }
        let allowed: Set<String> = ["schemaVersion", "id", "name", "version", "author", "description", "permissions"]
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              Set(object.keys) == allowed else {
            throw ManifestError.invalid("Use the exact manifest fields. Executable files and extra fields are not accepted.")
        }
        guard let manifest = try? JSONDecoder().decode(ModuleManifest.self, from: data) else {
            throw ManifestError.invalid("The manifest is invalid or declares unknown permissions.")
        }
        try manifest.validate()
        return manifest
    }

    func validate() throws {
        guard schemaVersion == 1 else { throw ManifestError.invalid("This manifest schema version is not supported.") }
        guard id.range(of: "^[a-z0-9]+(?:[.-][a-z0-9]+)+$", options: .regularExpression) != nil,
              id.count <= 100, id != Self.ouraID else {
            throw ManifestError.invalid("Use a unique identifier with lowercase letters, numbers, dots or hyphens. The included connector’s identifier is reserved.")
        }
        guard version.range(of: "^[0-9]{1,4}\\.[0-9]{1,4}\\.[0-9]{1,4}$", options: .regularExpression) != nil else {
            throw ManifestError.invalid("The version must use the format 1.0.0.")
        }
        for (value, limit) in [(name, 80), (author, 100), (description, 600)] {
            guard !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  value.count <= limit,
                  !value.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else {
                throw ManifestError.invalid("Name, author and description must be short, nonempty text without control characters.")
            }
        }
        guard Set(permissions).count == permissions.count, permissions.count <= ModulePermission.allCases.count else {
            throw ManifestError.invalid("The permissions list contains duplicate values.")
        }
    }
}

enum ManifestError: LocalizedError {
    case invalid(String)
    var errorDescription: String? {
        switch self { case .invalid(let message): return message }
    }
}

@MainActor
final class ModuleStore: ObservableObject {
    static let shared = ModuleStore()
    static let ouraPreferenceKey = "modules.oura.enabled"
    private static let manifestPreferenceKey = "modules.imported.v1"
    private let defaults: UserDefaults

    @Published var ouraEnabled: Bool {
        didSet { defaults.set(ouraEnabled, forKey: Self.ouraPreferenceKey) }
    }
    @Published private(set) var manifests: [ModuleManifest]

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        ouraEnabled = defaults.bool(forKey: Self.ouraPreferenceKey)
        let saved = defaults.data(forKey: Self.manifestPreferenceKey)
        let decoded = saved.flatMap { try? JSONDecoder().decode([ModuleManifest].self, from: $0) } ?? []
        var seen = Set<String>()
        manifests = Array(decoded.filter {
            (try? $0.validate()) != nil && seen.insert($0.id).inserted
        }.prefix(20))
    }

    func importManifest(data: Data) throws -> ModuleManifest {
        let manifest = try ModuleManifest.decode(data)
        guard manifests.count < 20 else { throw ManifestError.invalid("You can save up to 20 manifests. Remove one before importing another.") }
        guard !manifests.contains(where: { $0.id == manifest.id }) else {
            throw ManifestError.invalid("A manifest with this identifier already exists. Remove it before importing another version.")
        }
        manifests.append(manifest)
        persist()
        return manifest
    }

    func remove(id: String) {
        manifests.removeAll { $0.id == id }
        persist()
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(manifests) { defaults.set(data, forKey: Self.manifestPreferenceKey) }
    }
}

@MainActor
struct ModulesView: View {
    @ObservedObject var store: ModuleStore
    @Environment(\.dismiss) private var dismiss
    var onConnect: (() -> Void)?
    @State private var showImporter = false
    @State private var importMessage: String?
    @State private var selectedManifest: ModuleManifest?

    init(store: ModuleStore? = nil, onConnect: (() -> Void)? = nil) {
        self.store = store ?? .shared
        self.onConnect = onConnect
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Obs.canvas
                ScrollView {
                    VStack(alignment: .leading, spacing: 26) {
                        intro
                        ouraCard
                        importedSection
                        privacyNote
                        formatGuide
                    }
                    .padding(24)
                    .frame(maxWidth: 600)
                    .frame(maxWidth: .infinity)
                }
            }
            .navigationTitle("Modules")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } } }
            .fileImporter(isPresented: $showImporter, allowedContentTypes: [.json], allowsMultipleSelection: false, onCompletion: importFile)
            .alert("Import manifest", isPresented: Binding(get: { importMessage != nil }, set: { if !$0 { importMessage = nil } })) {
                Button("OK", role: .cancel) { importMessage = nil }
            } message: { Text(importMessage ?? "") }
            .sheet(item: $selectedManifest) { manifest in
                ModuleManifestDetail(manifest: manifest) {
                    store.remove(id: manifest.id)
                    selectedManifest = nil
                }
            }
        }
        .tint(Obs.ink)
    }

    private var intro: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Your health.\nYour sources.")
                .font(Obs.serif(34, .medium)).foregroundStyle(Obs.ink)
                .fixedSize(horizontal: false, vertical: true)
            Text("Choose your devices and review their permissions.")
                .font(Obs.prose(15)).foregroundStyle(Obs.ink2)
        }
    }

    private var ouraCard: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 14) {
                Image(systemName: "circle.circle")
                    .font(.system(size: 30, weight: .light)).foregroundStyle(Obs.ink)
                    .frame(width: 58, height: 58)
                    .background(Obs.good.opacity(0.1), in: RoundedRectangle(cornerRadius: 18))
                VStack(alignment: .leading, spacing: 4) {
                    Text("Oura Ring").font(Obs.prose(20, .semibold)).foregroundStyle(Obs.ink)
                    Text("Included connector · open_oura").font(Obs.prose(12)).foregroundStyle(Obs.muted)
                }
                Spacer(minLength: 0)
            }

            Text("Connect your ring over Bluetooth and process your history on this device.")
                .font(Obs.prose(14)).foregroundStyle(Obs.ink2)

            HStack(spacing: 8) {
                permissionChip("Bluetooth", symbol: "antenna.radiowaves.left.and.right")
                permissionChip("Local data", symbol: "internaldrive")
            }

            Divider().overlay(Obs.rule)
            Toggle(isOn: $store.ouraEnabled) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(store.ouraEnabled ? "Module enabled" : "Enable module")
                        .font(Obs.prose(15, .semibold)).foregroundStyle(Obs.ink)
                    Text("Allow a connection to your ring.")
                        .font(Obs.prose(12)).foregroundStyle(Obs.muted)
                }
            }
            .tint(Obs.good)

            if store.ouraEnabled, let onConnect {
                Button(action: onConnect) {
                    HStack {
                        Text("Connect my ring")
                        Spacer()
                        Image(systemName: "arrow.up.right")
                    }
                    .font(Obs.prose(15, .semibold)).foregroundStyle(Obs.ink)
                    .padding(14)
                    .background(Obs.good.opacity(0.13), in: RoundedRectangle(cornerRadius: 14))
                }
                .buttonStyle(.plain)
            }
            Text("This connector is included in the app. Disabling it blocks new connections and keeps your history. Apple Health is authorized separately.")
                .font(Obs.prose(12)).foregroundStyle(Obs.muted)
        }
        .obsCard(padding: 22, radius: 26)
    }

    private var importedSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Your library").font(Obs.prose(19, .semibold)).foregroundStyle(Obs.ink)
                Spacer()
                Text("\(store.manifests.count) / 20").font(Obs.mono(11)).foregroundStyle(Obs.muted)
            }
            if store.manifests.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Image(systemName: "square.stack.3d.up").font(.system(size: 26, weight: .light)).foregroundStyle(Obs.muted)
                    Text("Room for new sources").font(Obs.prose(16, .medium)).foregroundStyle(Obs.ink)
                    Text("Import a JSON manifest to review its author, version and declared permissions.")
                        .font(Obs.prose(13)).foregroundStyle(Obs.ink2)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .obsCard(padding: 20, radius: 22)
            } else {
                ForEach(store.manifests) { manifest in
                    Button { selectedManifest = manifest } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "shippingbox").font(.system(size: 22, weight: .light)).foregroundStyle(Obs.ink2)
                                .frame(width: 40, height: 40)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(manifest.name).font(Obs.prose(16, .semibold)).foregroundStyle(Obs.ink)
                                Text("v\(manifest.version) · Manifest only").font(Obs.prose(12)).foregroundStyle(Obs.muted)
                            }
                            Spacer(minLength: 4)
                            Image(systemName: "chevron.right").font(.system(size: 12, weight: .medium)).foregroundStyle(Obs.muted)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .obsCard(padding: 16, radius: 20)
                    }.buttonStyle(.plain)
                }
            }
            Button { showImporter = true } label: {
                Label("Import manifest", systemImage: "plus")
                    .font(Obs.prose(15, .semibold)).foregroundStyle(Obs.ink)
                    .frame(maxWidth: .infinity).padding(17)
                    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 18))
                    .overlay(RoundedRectangle(cornerRadius: 18).stroke(Obs.rule, lineWidth: 1))
            }.buttonStyle(.plain)
        }
    }

    private var privacyNote: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "info.circle").font(.system(size: 18)).foregroundStyle(Obs.muted)
            VStack(alignment: .leading, spacing: 7) {
                Text("Visible permissions. Your choice.").font(Obs.prose(14, .semibold)).foregroundStyle(Obs.ink)
                Text("Imported files contain unverified metadata. They do not install code, connect devices or grant permissions. New devices need a compatible adapter in a future release.")
                    .font(Obs.prose(12)).foregroundStyle(Obs.ink2)
                Text("Importing a manifest is not a security audit.")
                    .font(Obs.prose(12)).foregroundStyle(Obs.muted)
            }
        }
        .padding(.horizontal, 2)
    }

    private var formatGuide: some View {
        DisclosureGroup {
            VStack(alignment: .leading, spacing: 12) {
                Text("JSON · version 1 · 64 KB maximum. All fields are required. Recognized permissions: bluetooth, health-read, health-write, network and local-storage.")
                    .font(Obs.prose(12)).foregroundStyle(Obs.ink2)
                Text(ModuleManifest.exampleJSON).font(Obs.mono(11)).foregroundStyle(Obs.ink2)
                    .textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
            }.padding(.top, 12)
        } label: {
            Text("Manifest format").font(Obs.prose(14, .medium)).foregroundStyle(Obs.ink2)
        }
        .obsCard(padding: 18, radius: 20)
    }

    private func permissionChip(_ title: String, symbol: String) -> some View {
        Label(title, systemImage: symbol).font(Obs.prose(11, .medium)).foregroundStyle(Obs.ink2)
            .padding(.horizontal, 10).padding(.vertical, 7)
            .background(Obs.rule.opacity(0.5), in: Capsule())
    }

    private func importFile(_ result: Result<[URL], Error>) {
        do {
            let urls = try result.get()
            guard let url = urls.first else { return }
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
            guard size <= ModuleManifest.maximumBytes else { throw ManifestError.invalid("The file exceeds the 64 KB limit.") }
            let handle = try FileHandle(forReadingFrom: url)
            defer { try? handle.close() }
            let data = try handle.read(upToCount: ModuleManifest.maximumBytes + 1) ?? Data()
            let manifest = try store.importManifest(data: data)
            importMessage = "\(manifest.name) was added to your library for review. No adapter was installed or enabled."
        } catch {
            if (error as NSError).code != NSUserCancelledError { importMessage = error.localizedDescription }
        }
    }
}

private struct ModuleManifestDetail: View {
    let manifest: ModuleManifest
    let onRemove: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                Obs.canvas
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        VStack(alignment: .leading, spacing: 9) {
                            Text("IMPORTED MANIFEST").font(Obs.mono(10, .medium)).tracking(1.3).foregroundStyle(Obs.muted)
                            Text(manifest.name).font(Obs.serif(30, .medium)).foregroundStyle(Obs.ink)
                            Text("v\(manifest.version) · \(manifest.author)").font(Obs.prose(14)).foregroundStyle(Obs.ink2)
                            Text(manifest.id).font(Obs.mono(11)).foregroundStyle(Obs.muted).textSelection(.enabled)
                        }
                        Text(manifest.description).font(Obs.prose(15)).foregroundStyle(Obs.ink2)
                        VStack(alignment: .leading, spacing: 16) {
                            Text("Declared permissions").font(Obs.prose(17, .semibold)).foregroundStyle(Obs.ink)
                            if manifest.permissions.isEmpty {
                                Text("No declared permissions.").font(Obs.prose(14)).foregroundStyle(Obs.muted)
                            }
                            ForEach(manifest.permissions) { permission in
                                Label(permission.title, systemImage: permission.symbol)
                                    .font(Obs.prose(14)).foregroundStyle(permission == .network ? Obs.warn : Obs.ink2)
                            }
                            if manifest.permissions.contains(.network) {
                                Text("Declares network access. Review its destinations and the data it would send before implementing an adapter.")
                                    .font(Obs.prose(12)).foregroundStyle(Obs.warn)
                            }
                        }.frame(maxWidth: .infinity, alignment: .leading).obsCard(padding: 22, radius: 24)
                        Text("The author declares these permissions. They have not been verified or granted. This manifest has no executable adapter in the app.")
                            .font(Obs.prose(13)).foregroundStyle(Obs.muted)
                        Button(role: .destructive, action: onRemove) {
                            Label("Remove manifest", systemImage: "trash").font(Obs.prose(14, .medium))
                                .frame(maxWidth: .infinity).padding(16)
                        }
                    }.padding(24)
                }
            }
            .navigationTitle("Module details").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() }.foregroundStyle(Obs.ink) } }
        }
        .tint(Obs.ink)
    }
}
