import SwiftUI
import UniformTypeIdentifiers

// The SwiftUI screens for OuraApp. Data types live in Models.swift, the model/FFI
// orchestration in Core.swift, the reusable charts/cells in Components.swift, and the
// full-page sleep/activity reports in Reports.swift.
// SIBLING CLIENT: the web dashboard (dashboard/web/app.js) renders the SAME summary
// JSON — a user-facing change here usually belongs there too (docs/clients-web-and-ios.md).

// The home's unified "today": last night's sleep and that day's activity as ONE unit,
// each region tappable to open its own detail (sleep → SleepDetail, activity →
// ActivityDetail). Mirrors the web dashboard's day card. Previous days live behind
// "show all days" (AllDaysView → DayDetailView, which shows the same pairing).
struct TodayCard: View {
    let s: Summary
    let day: String
    let onSleep: () -> Void
    let onActivity: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(day).font(Obs.mono(12, .medium)).foregroundStyle(Obs.ink)
                .padding(.bottom, 14)

            // night — tap for the hypnogram + breakdown + that night's vitals
            if let n = s.night(forDay: day) {
                Button(action: onSleep) {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            ObsTag("Sleep", icon: "moon.fill")
                            Spacer()
                            Text(n.in_bed_h.map { String(format: "%.1fh", $0) } ?? "–")
                                .font(Obs.mono(11)).foregroundStyle(Obs.ink2)
                            Image(systemName: "chevron.right").font(.system(size: 11)).foregroundStyle(Obs.trace)
                        }
                        Text("\(n.start ?? "–") → \(n.end ?? "–")")
                            .font(Obs.mono(12)).foregroundStyle(Obs.ink2)
                        if n.hasHypnogram { Hypnogram(stages: n.stages!, height: 28) }
                        else if let e = n.efficiency {
                            Text("Efficiency \(Int(e))%").font(Obs.mono(12))
                                .foregroundStyle(e >= 85 ? Obs.good : (e < 75 ? Obs.bad : Obs.ink2))
                        }
                    }
                    .contentShape(Rectangle())
                }.buttonStyle(.plain)

                Rectangle().fill(Obs.trace.opacity(0.4)).frame(height: 0.5)
                    .padding(.vertical, 16)
            }

            // activity — tap for the movement ridge + steps/kcal + this day's workouts
            Button(action: onActivity) {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        ObsTag("Activity", icon: "figure.walk")
                        Spacer()
                        if let st = s.activity_daily[day] {
                            Text("\(Int(st.steps ?? 0)) steps").font(Obs.mono(11)).foregroundStyle(Obs.ink2)
                            Text("· \(Int(st.active_kcal ?? 0)) kcal").font(Obs.mono(11)).foregroundStyle(Obs.ink2)
                        }
                        Image(systemName: "chevron.right").font(.system(size: 11)).foregroundStyle(Obs.trace)
                    }
                    MovementRidge(profile: s.activity_profile[day] ?? [])
                    ForEach(Array(s.workoutsOn(day).prefix(2))) { w in
                        SessionRow(label: w.label, durationMin: w.durationMin, startHM: w.startHM)
                    }
                }
                .contentShape(Rectangle())
            }.buttonStyle(.plain)
        }
        .obsCard()
    }
}

// "show all days" → a page listing every day; tap one for its full report.
struct AllDaysView: View {
    let s: Summary
    @Environment(\.dayAnalysis) private var analysis
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        let s = analysis?.summary ?? s
        NavigationStack {
            ZStack {
                Obs.canvas.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 14) {
                        ForEach(s.days, id: \.self) { day in
                            NavigationLink {
                                DayReportView(s: s, day: day, tab: .sleep)
                            } label: {
                                HStack(spacing: 12) {
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(day).font(Obs.mono(13, .medium)).foregroundStyle(Obs.ink)
                                        if let st = s.activity_daily[day] {
                                            Text("\(Int(st.steps ?? 0)) steps · \(Int(st.active_kcal ?? 0)) kcal")
                                                .font(Obs.mono(11)).foregroundStyle(Obs.ink2)
                                        }
                                    }
                                    Spacer(minLength: 8)
                                    if let n = s.night(forDay: day), n.hasHypnogram {
                                        Hypnogram(stages: n.stages!, height: 20).frame(width: 96)
                                    }
                                    Image(systemName: "chevron.right").font(.system(size: 11)).foregroundStyle(Obs.trace)
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(24)
                }
            }
            .navigationTitle("all days")
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } } }
        }
    }
}

// Pair + sync from a real ring: paste the auth key (exported on the desktop), connect
// over BLE, drain history into the writable DB. BLE only works on a physical device.
struct SyncView: View {
    @ObservedObject var ring: RingSync
    let onSynced: (SyncReport) -> Void
    let onReset: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var key = Keychain.loadKey() ?? ""
    @ObservedObject private var diag = RingDiag.shared
    @ObservedObject private var store = DiagStore.shared
    @State private var diagnosticFile: URL?
    @State private var showKey = false
    @State private var clockReport: String?
    @State private var confirmReset = false
    @State private var confirmWipeRing = false
    @State private var backupFile: URL?
    @State private var showRestorePicker = false
    @State private var restoreNote: String?
    @FocusState private var keyFocused: Bool

    static let backupStamp: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd-HHmm"; return f
    }()

    /// Validate the chosen file before it replaces anything: a truncated download or
    /// the wrong file entirely must not destroy a working database.
    private func restore(from result: Result<[URL], Error>) async -> String {
        guard case .success(let urls) = result, let picked = urls.first else { return "Restore cancelled." }
        let scoped = picked.startAccessingSecurityScopedResource()
        defer { if scoped { picked.stopAccessingSecurityScopedResource() } }
        let staging = FileManager.default.temporaryDirectory
            .appendingPathComponent("restore-\(UUID().uuidString).db")
        defer { try? FileManager.default.removeItem(at: staging) }
        do { try FileManager.default.copyItem(at: picked, to: staging) }
        catch { return "Could not read that file: \(error.localizedDescription)" }

        if ring.busy { ring.pause() }
        WorkCoordinator.shared.invalidateAnalysis()
        await WorkGate.shared.acquire()
        guard WorkCoordinator.shared.available else {
            await WorkGate.shared.release()
            return "Restore paused. Keep the app open and try again."
        }
        let destination = DB.url
        let failure: String? = await Task.detached {
            do {
                try DatabaseRestore.restore(candidate: staging, destination: destination)
                return nil
            } catch { return error.localizedDescription }
        }.value
        await WorkGate.shared.release()
        if let failure { return "Restore failed: \(failure) Your previous data was preserved." }
        return "Restored. The next sync continues from where the backup left off."
    }

    private var validKey: Bool {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.utf8.count == 32 && trimmed.utf8.allSatisfy {
            (48...57).contains($0) || (65...70).contains($0) || (97...102).contains($0)
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    header
                    if ring.connectionIssue != nil { syncStatus }
                    else { preparation }
                    if !ring.busy { pairingKey }
                    connection
                    support
                    BuildStamp()
                }
                .frame(maxWidth: 520)
                .padding(.horizontal, 24)
                .padding(.top, 20)
                .padding(.bottom, 32)
                .frame(maxWidth: .infinity)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(Obs.paper)
            .navigationTitle("Your ring")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(Obs.ink)
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { keyFocused = false }
                }
            }
            .alert("Reset local sync data?", isPresented: $confirmReset) {
                Button("Cancel", role: .cancel) {}
                Button("Reset local data", role: .destructive) {
                    Task { if await ring.resetLocalDatabase() { onReset() } }
                }
            } message: {
                Text("This removes the synced data on this iPhone. Your next sync will download the history still available on your ring.")
            }
            .alert("Factory-reset \(ring.knownSerial ?? "the ring")?", isPresented: $confirmWipeRing) {
                Button("Cancel", role: .cancel) {}
                Button("Erase the ring", role: .destructive) {
                    let serial = ring.knownSerial ?? ""
                    let current = key
                    Task {
                        if await ring.factoryReset(keyHex: current, confirmSerial: serial) {
                            key = ""
                            showKey = false
                        }
                    }
                }
            } message: {
                Text("Erases the ring's pairing key, its Bluetooth bonds, any events it hasn't sent yet, and your stored body profile. Sync first if you want those events. This cannot be undone — but the ring stays yours: pair it again right here afterwards.")
            }
        }
        .tint(Obs.ink)
        // Sync belongs to RingSync and continues when this panel is dismissed.
        .sheet(isPresented: Binding(get: { diagnosticFile != nil }, set: { if !$0 { diagnosticFile = nil } })) {
            if let diagnosticFile { DiagnosticsShare(url: diagnosticFile) }
        }
        .sheet(isPresented: Binding(get: { backupFile != nil }, set: { if !$0 { backupFile = nil } })) {
            if let backupFile { DiagnosticsShare(url: backupFile) }
        }
        .fileImporter(isPresented: $showRestorePicker,
                      allowedContentTypes: [.data],
                      allowsMultipleSelection: false) { result in
            Task {
                restoreNote = "Checking backup…"
                restoreNote = await restore(from: result)
                if restoreNote?.hasPrefix("Restored") == true { onReset() }
            }
        }
        .presentationDragIndicator(.visible)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            HealthRingIllustration(size: 180).frame(maxWidth: .infinity)
            Text("Sensor illustration · not a live reading").font(Obs.prose(10)).foregroundStyle(Obs.muted)
                .frame(maxWidth: .infinity).padding(.bottom, 10)
            Text("Pair your ring")
                .font(.system(.largeTitle, design: .serif))
                .foregroundStyle(Obs.ink)
            Text("Bring your health history to this iPhone.")
                .font(.subheadline)
                .foregroundStyle(Obs.ink2)
        }
    }

    private var preparation: some View {
        VStack(alignment: .leading, spacing: 18) {
            setupRow(icon: "bolt", title: "Place your ring on its charger",
                     detail: "Keep it close to this iPhone.")
            setupRow(icon: "antenna.radiowaves.left.and.right", title: "Free up the Bluetooth connection",
                     detail: "Turn off Bluetooth on other phones using the Oura app. Keep it on here.")
        }
    }

    private func setupRow(icon: String, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .regular))
                .foregroundStyle(Obs.muted)
                .frame(width: 24, height: 24)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.subheadline.weight(.medium)).foregroundStyle(Obs.ink)
                Text(detail).font(.subheadline).foregroundStyle(Obs.ink2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var pairingKey: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Pairing key").font(.subheadline.weight(.semibold)).foregroundStyle(Obs.ink)
            HStack(spacing: 8) {
                Group {
                    if showKey { TextField("Paste your pairing key", text: $key) }
                    else { SecureField("Paste your pairing key", text: $key) }
                }
                .font(.system(.subheadline, design: .monospaced))
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .focused($keyFocused)
                .accessibilityLabel("Pairing key")
                .disabled(ring.busy)
                Button { showKey.toggle() } label: {
                    Image(systemName: showKey ? "eye.slash" : "eye")
                        .frame(width: 44, height: 44)
                }
                .accessibilityLabel(showKey ? "Hide pairing key" : "Show pairing key")
            }
            .foregroundStyle(Obs.ink)
            .padding(.leading, 14)
            .padding(.trailing, 4)
            .padding(.vertical, 4)
            .background(Obs.rule.opacity(0.25), in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(keyFocused ? Obs.muted : Obs.rule))
            Text(!key.isEmpty && !validKey
                 ? "Use all 32 characters: numbers 0–9 and letters A–F."
                 : "Paste the 32-character key exported on your computer, or pair a reset ring below.")
                .font(.footnote)
                .foregroundStyle(Obs.ink2)
                .fixedSize(horizontal: false, vertical: true)
            pairReset
        }
    }

    /// Adopt a factory-reset ring without a computer: mint the key on this iPhone.
    private var pairReset: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                keyFocused = false
                Task { if let minted = await ring.pair() { key = minted } }
            } label: {
                Label("Pair a factory-reset ring", systemImage: "key")
                    .font(.subheadline.weight(.medium))
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .foregroundStyle(Obs.ink)
                    .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Obs.rule))
            }
            .buttonStyle(.plain)
            .disabled(ring.busy)
            Text("Mints a new key on this iPhone and installs it on the ring. Only works on a ring that has been factory-reset — it replaces nothing on a ring that already has a key. Reveal and write the key down afterwards: it cannot be read back off the ring.")
                .font(.footnote)
                .foregroundStyle(Obs.ink2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, 4)
    }

    @ViewBuilder
    private var syncStatus: some View {
        if ring.busy || !ring.status.isEmpty {
            HStack(alignment: .top, spacing: 12) {
                if ring.busy {
                    ProgressView().tint(Obs.ink).frame(width: 24, height: 24)
                } else {
                    Image(systemName: ring.lastReport != nil ? "checkmark.circle" : "info.circle")
                        .font(.title3)
                        .foregroundStyle(ring.lastReport != nil ? Obs.good : Obs.ink2)
                }
                VStack(alignment: .leading, spacing: 6) {
                    Text(ring.busy ? "Sync in progress" : (ring.connectionIssue ?? (ring.lastReport != nil ? "Your ring is up to date" : "Sync status")))
                        .font(.subheadline.weight(.semibold)).foregroundStyle(Obs.ink)
                    Text(ring.status)
                        .font(.subheadline).foregroundStyle(Obs.ink2)
                        .fixedSize(horizontal: false, vertical: true)
                    if ring.busy {
                        Text("Keep the app open. If the connection drops, sync resumes automatically.")
                            .font(.footnote).foregroundStyle(Obs.ink2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(Obs.rule.opacity(0.3), in: RoundedRectangle(cornerRadius: 16))
        }
    }

    private var connection: some View {
        VStack(alignment: .leading, spacing: 16) {
            if ring.connectionIssue == nil { syncStatus }
            if ring.busy {
                Button { ring.pause() } label: {
                    Label("Pause sync", systemImage: "pause")
                        .font(.body.weight(.medium))
                        .frame(maxWidth: .infinity, minHeight: 52)
                        .foregroundStyle(Obs.ink)
                        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Obs.rule))
                }
                .buttonStyle(.plain)
            } else {
                Button {
                    keyFocused = false
                    Task {
                        if let report = await ring.run(keyHex: key) { onSynced(report) }
                    }
                } label: {
                    HStack(spacing: 10) {
                        Text("Connect & sync")
                        Image(systemName: "arrow.right")
                    }
                    .font(.body.weight(.semibold))
                    .frame(maxWidth: .infinity, minHeight: 54)
                    .foregroundStyle(validKey ? Obs.paper : Obs.muted)
                    .background(validKey ? Obs.ink : Obs.rule, in: RoundedRectangle(cornerRadius: 14))
                }
                .buttonStyle(.plain)
                .disabled(!validKey)
                Text("Your first sync may take a few minutes.")
                    .font(.footnote).foregroundStyle(Obs.ink2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // Help & diagnostics: one quiet card of grouped rows instead of nested disclosures.
    // Everyday actions first, the technical transcript one tap deeper, destructive last.
    private var support: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("Help & diagnostics")
                    .font(.subheadline.weight(.semibold)).foregroundStyle(Obs.ink)
                Spacer()
                Text(appVersion).font(Obs.mono(11)).foregroundStyle(Obs.muted)
            }
            VStack(spacing: 0) {
                SupportRow(icon: "externaldrive", title: "Check saved data",
                           detail: ring.busy ? "Available after sync" : "Verify the records on this iPhone",
                           disabled: ring.busy) { Task { await ring.checkDatabase() } }
                SupportDivider()
                SupportRow(icon: "square.and.arrow.up", title: "Share diagnostic report",
                           detail: "Logs and clock details, no ring key") {
                    Task {
                        let url = await Task.detached { DiagStore.shared.exportFile() }.value
                        if let url { diagnosticFile = url }
                    }
                }
                SupportDivider()
                SupportRow(icon: "externaldrive.badge.icloud", title: "Export raw ring data",
                           detail: "A copy of the ring records, for analysis on a computer",
                           disabled: ring.busy) {
                    Task { if let url = await ring.exportRawDatabase() { diagnosticFile = url } }
                }
                SupportDivider()
                NavigationLink {
                    RawDataView()
                } label: {
                    SupportRowLabel(icon: "waveform.path.ecg", title: "Raw data & charts",
                                    detail: "Browse every event the ring sent, and chart any field",
                                    trailing: "chevron.right")
                }
                .buttonStyle(.plain)
                SupportDivider()
                SupportRow(icon: "arrow.down.doc", title: "Back up data",
                           detail: "One consistent file with every event synced from the ring. The pairing key is not in it \u{2014} it stays in this iPhone's Keychain.",
                           disabled: ring.busy) {
                    Task {
                        let stamp = Self.backupStamp.string(from: Date())
                        await WorkGate.shared.acquire()
                        let made = await Task.detached { () -> URL? in
                            let name = "oura-backup-\(stamp).db"
                            let dest = FileManager.default.temporaryDirectory
                                .appendingPathComponent(name)
                            do {
                                _ = try backupDatabase(dbPath: DB.readPath(), destPath: dest.path)
                                return dest
                            } catch { return nil }
                        }.value
                        await WorkGate.shared.release()
                        if let made { backupFile = made }
                        else { restoreNote = "Backup failed \u{2014} nothing written." }
                    }
                }
                SupportDivider()
                SupportRow(icon: "arrow.up.doc", title: "Restore from a backup",
                           detail: restoreNote ?? "Replace what this iPhone holds with a backup file",
                           disabled: ring.busy) { showRestorePicker = true }
                SupportDivider()
                NavigationLink {
                    TechnicalReportsView(clockReport: $clockReport)
                } label: {
                    SupportRowLabel(icon: "doc.text.magnifyingglass", title: "Technical reports",
                                    detail: technicalSummary, trailing: "chevron.right")
                }
                .buttonStyle(.plain)
            }
            .background(Obs.rule.opacity(0.3), in: RoundedRectangle(cornerRadius: 16))

            VStack(spacing: 0) {
                SupportRow(icon: "trash", title: "Reset local sync data",
                           detail: "Removes saved data from this iPhone. The next sync restores what your ring still holds.",
                           tint: Obs.alert, disabled: ring.busy) { confirmReset = true }
                SupportDivider()
                SupportRow(icon: "exclamationmark.triangle", title: "Factory-reset the ring",
                           detail: ring.knownSerial == nil
                               ? "Available once this iPhone has talked to your ring."
                               : "Wipes the ring itself, not just this phone. Pair it again afterwards \u{2014} no computer needed.",
                           tint: Obs.alert,
                           disabled: ring.busy || ring.knownSerial == nil || !validKey) { confirmWipeRing = true }
            }
            .background(Obs.alert.opacity(0.06), in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Obs.alert.opacity(0.18)))
        }
    }

    private var appVersion: String {
        // The plain swiftc simulator build ships Info.plist with unexpanded $(…) values.
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? ""
        let build = info?["CFBundleVersion"] as? String ?? ""
        guard !short.isEmpty, !short.contains("$(") else { return "" }
        return build.isEmpty || build.contains("$(") ? "v\(short)" : "v\(short) (\(build))"
    }

    private var technicalSummary: String {
        var parts: [String] = []
        if !store.incidents.isEmpty { parts.append("\(store.incidents.count) incidents") }
        if !store.sessions.isEmpty { parts.append("\(store.sessions.count) sessions") }
        if diag.totalLines > 0 { parts.append("\(diag.totalLines) log lines") }
        return parts.isEmpty ? "Ring clock, incidents and the live log" : parts.joined(separator: " · ")
    }
}

/// One tappable row of the Help & diagnostics card.
private struct SupportRow: View {
    let icon: String
    let title: String
    let detail: String
    var tint: Color = Obs.ink
    var disabled = false
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            SupportRowLabel(icon: icon, title: title, detail: detail, tint: tint, trailing: nil)
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .opacity(disabled ? 0.45 : 1)
    }
}

private struct SupportRowLabel: View {
    let icon: String
    let title: String
    let detail: String
    var tint: Color = Obs.ink
    let trailing: String?
    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .regular))
                .foregroundStyle(tint == Obs.ink ? Obs.ink2 : tint)
                .frame(width: 32, height: 32)
                .background(Obs.paper.opacity(0.85), in: Circle())
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.subheadline.weight(.medium)).foregroundStyle(tint)
                Text(detail).font(.footnote).foregroundStyle(Obs.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            if let trailing {
                Image(systemName: trailing).font(.system(size: 12, weight: .semibold)).foregroundStyle(Obs.trace)
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
        .frame(minHeight: 56)
        .contentShape(Rectangle())
    }
}

private struct SupportDivider: View {
    var body: some View { Rectangle().fill(Obs.rule).frame(height: 0.6).padding(.leading, 60) }
}

/// The technical transcript on its own page: ring clock anchors, recorded incidents,
/// previous sessions and the live log, each with a copy action.
private struct TechnicalReportsView: View {
    @Binding var clockReport: String?
    @ObservedObject private var diag = RingDiag.shared
    @ObservedObject private var store = DiagStore.shared
    @State private var copied: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                section("Ring clock", copy: clockReport) {
                    Text(clockReport ?? "No summary rendered yet.")
                        .font(.caption.monospaced()).foregroundStyle(clockReport == nil ? Obs.muted : Obs.ink2)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                section("Incidents · \(store.incidents.count)", copy: nil) {
                    if store.incidents.isEmpty {
                        Text("No incidents recorded.").font(.caption).foregroundStyle(Obs.muted)
                    }
                    ForEach(store.incidents.prefix(8)) { item in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack(alignment: .firstTextBaseline) {
                                Text(item.title).font(.caption.weight(.medium)).foregroundStyle(Obs.ink)
                                Spacer()
                                Text(item.date, format: .dateTime.month(.abbreviated).day().hour().minute())
                                    .font(.caption2).foregroundStyle(Obs.muted)
                            }
                            Text(item.preview).font(.caption.monospaced()).foregroundStyle(Obs.ink2)
                                .lineLimit(5).frame(maxWidth: .infinity, alignment: .leading)
                            copyButton("incident-\(item.id)", text: item.body)
                        }
                        .padding(10)
                        .background(Obs.paper.opacity(0.6), in: RoundedRectangle(cornerRadius: 10))
                    }
                }
                if !store.sessions.isEmpty {
                    section("Previous sessions · \(store.sessions.count)", copy: nil) {
                        ForEach(store.sessions.prefix(4)) { item in
                            HStack {
                                Text(item.title).font(Obs.mono(11)).foregroundStyle(Obs.ink2)
                                Spacer()
                                copyButton("session-\(item.id)", text: item.body)
                            }
                        }
                    }
                }
                section("Current session · \(diag.totalLines) lines", copy: nil) {
                    HStack {
                        Spacer()
                        Button(copied == "summary" ? "Copied" : "Copy summary") {
                            Task {
                                let text = await Task.detached { DiagStore.shared.exportSummary() }.value
                                UIPasteboard.general.string = text
                                flash("summary")
                            }
                        }
                        .font(.caption.weight(.medium)).foregroundStyle(Obs.ink).frame(minHeight: 32)
                    }
                    if diag.totalLines > 0 {
                        ScrollView {
                            VStack(alignment: .leading, spacing: 2) {
                                ForEach(Array(diag.tail.enumerated()), id: \.offset) { _, line in
                                    Text(line).font(Obs.mono(9)).foregroundStyle(Obs.ink2)
                                        .lineLimit(3).frame(maxWidth: .infinity, alignment: .leading)
                                }
                            }
                            .padding(8)
                        }
                        .defaultScrollAnchor(.bottom)
                        .frame(maxHeight: 260)
                        .background(Obs.paper.opacity(0.6), in: RoundedRectangle(cornerRadius: 10))
                    } else {
                        Text("Nothing logged yet.").font(.caption).foregroundStyle(Obs.muted)
                    }
                }
            }
            .frame(maxWidth: 520)
            .padding(.horizontal, 24).padding(.vertical, 20)
            .frame(maxWidth: .infinity)
        }
        .background(Obs.paper)
        .navigationTitle("Technical reports")
        .navigationBarTitleDisplayMode(.inline)
        .task { if clockReport == nil { clockReport = await Task.detached { ClockReport.text() }.value } }
    }

    private func section<Content: View>(_ title: String, copy: String?, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(title.uppercased()).font(Obs.mono(10, .medium)).foregroundStyle(Obs.muted).tracking(0.8)
                Spacer()
                if let copy { copyButton(title, text: copy) }
            }
            content()
        }
        .padding(14)
        .background(Obs.rule.opacity(0.3), in: RoundedRectangle(cornerRadius: 16))
    }

    private func copyButton(_ id: String, text: String) -> some View {
        Button(copied == id ? "Copied" : "Copy") {
            UIPasteboard.general.string = text
            flash(id)
        }
        .font(.caption.weight(.medium)).foregroundStyle(Obs.ink).frame(minHeight: 32)
    }

    private func flash(_ id: String) {
        copied = id
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { if copied == id { copied = nil } }
    }
}

/// Human-readable rendering of the shared brain's `clock` block (per-boot ring clock
/// anchors), from the last rendered summary. Shown in Technical reports and appended
/// to the shared diagnostic report so a misdated night can be diagnosed remotely.
enum ClockReport {
    static func text() -> String? {
        guard let clock = SummaryCache.load()?.clock else { return nil }
        let fmt = DateFormatter(); fmt.dateFormat = "yyyy-MM-dd HH:mm"; fmt.timeZone = .current
        let day = { (unix: Int64?) -> String in unix.map { fmt.string(from: Date(timeIntervalSince1970: Double($0))) } ?? "–" }
        var lines: [String] = []
        for (i, e) in clock.epochs.enumerated() {
            let sources = (e.anchor_sources ?? []).joined(separator: ",")
            lines.append("boot \(i + 1): ds \(e.min_ds ?? 0)…\(e.max_ds ?? 0) (\(e.span_h ?? 0)h) synced \(day(e.capture_min))…\(day(e.capture_max)) anchors=\(e.anchors ?? 0)\(sources.isEmpty ? "" : " [\(sources)]") latest=\(day(e.latest_anchor_unix))")
        }
        for n in clock.undated_nights {
            lines.append("undated night: ds \(n.start_ds ?? 0)…\(n.end_ds ?? 0) \(n.in_bed_h ?? 0)h captured \(day(n.captured_unix)) (\(n.source ?? "?"))")
        }
        lines.append(contentsOf: clock.warnings.map { "warning: \($0)" })
        return lines.isEmpty ? nil : lines.joined(separator: "\n")
    }
}

struct DiagnosticsShare: UIViewControllerRepresentable {
    let url: URL
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [url], applicationActivities: nil)
    }
    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}

/// The top-bar sync affordance doubles as a live status light and the entry point
/// to diagnostics. Motion stays quiet: one slow continuous turn only while BLE is
/// active.
private struct SyncIndicatorButton: View {
    @ObservedObject var ring: RingSync
    let action: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var rotation = 0.0

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .stroke(Obs.rule, lineWidth: 0.8)
                Image(systemName: "arrow.triangle.2.circlepath")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(ring.busy ? Obs.ink : (ring.wasRecentlySynced ? Obs.good : Obs.ink2))
                    .rotationEffect(.degrees(rotation))
            }
            .frame(width: 31, height: 31)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(ring.busy ? "Ring sync in progress" : "Ring sync and diagnostics")
        .accessibilityHint("Opens sync status, logs, and manual controls")
        .onAppear(perform: updateAnimation)
        .onChange(of: ring.busy) { _, _ in updateAnimation() }
        .onChange(of: reduceMotion) { _, _ in updateAnimation() }
    }

    private func updateAnimation() {
        if ring.busy && !reduceMotion {
            rotation = 0
            withAnimation(.linear(duration: 1.6).repeatForever(autoreverses: false)) {
                rotation = 360
            }
        } else {
            withAnimation(.easeOut(duration: 0.2)) { rotation = 0 }
        }
    }
}

// ── root ─────────────────────────────────────────────────────────────────────
struct RootView: View {
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var ringMotion = HealthRingMotion()
    @State private var s: Summary?
    @State private var hasHydratedSummary = false
    @State private var automaticSyncInFlight = false
    @State private var pendingAutomaticRefresh = false
    @State private var summaryRefresh = SummaryRefreshPolicy()
    @State private var report: ReportSel?
    /// QA hooks for `simctl launch … -openSync` / `-openDay YYYY-MM-DD [activity]`, so
    /// a screen can be captured without driving the UI. Ignored in normal launches.
    private func applyLaunchArguments() {
        let args = CommandLine.arguments
        if args.contains("-openSync") { openConnection() }
        if args.contains("-openModules") { showModules = true }
        if args.contains("-openRing") { selectedTab = 1 }
        if args.contains("-openSettings") { selectedTab = 2 }
        if let index = args.firstIndex(of: "-openDay"), index + 1 < args.count {
            report = ReportSel(day: args[index + 1], sleep: !args.contains("activity"))
        }
    }
    @AppStorage("health.appearance") private var appearance = "system"
    @State private var selectedTab = 0
    @StateObject private var modules = ModuleStore.shared
    @State private var showAllDays = false
    @State private var showSync = false
    @State private var showProfile = false
    @State private var showModules = false
    @State private var connectAfterModules = false
    @State private var showSleepDebt = false
    @State private var vital: VitalKind?
    @State private var loadGeneration = 0
    @State private var isRefreshingSummary = false
    @StateObject private var ringOwner = HealthRingOwner()
    @State private var isRingBusy = false
    private var ring: RingSync { ringOwner.ring }
    // The header uses isRefreshingSummary, not per-unit labels. Retain the
    // progress sink without observing it and rebuilding the whole dashboard.
    @State private var modelProgress = ModelProgress()
    private func f(_ v: Double?, _ fallback: String = "–") -> String {
        v.map { "\(Int($0))" } ?? fallback
    }
    private func relAge(_ diff: Double) -> String {
        let a = abs((diff * 10).rounded() / 10)
        if diff < -0.05 { return "\(a) yr younger" }
        if diff > 0.05 { return "\(a) yr older" }
        return "in line"
    }
    private func localDay(_ date: Date = Date()) -> String {
        let c = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }
    private func displayedDayLabel(_ day: String, now: Date = Date()) -> String {
        if day == localDay(now) { return "today" }
        if let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: now),
           day == localDay(yesterday) { return "yesterday" }
        return day
    }
    private func latestLabel(date: String?, time: String? = nil) -> String {
        let day = date.map { String($0.suffix(5)) }
        let stamp = [day, time].compactMap { $0 }.joined(separator: " · ")
        return stamp.isEmpty ? "Last synced" : "Latest · \(stamp)"
    }
    private var sectionAccent: Color {
        selectedTab == 0 ? Obs.homeAccent : selectedTab == 1 ? Obs.accent : Obs.settingsAccent
    }
    private var colorScheme: ColorScheme? {
        appearance == "dark" ? .dark : appearance == "light" ? .light : nil
    }
    private func openConnection() {
        if modules.ouraEnabled { showSync = true }
        else { selectTab(1) }
    }
    var body: some View {
        TabView(selection: Binding(get: { selectedTab }, set: selectTab)) {
            NavigationStack {
                Group {
                    if let s { content(s) }
                    else {
                        VStack(spacing: 14) {
                            ProgressView().tint(Obs.homeAccent)
                            Text("Preparing your data…").font(.subheadline).foregroundStyle(Obs.ink2)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
                .background(Obs.paper)
                .navigationTitle("Home")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .principal) { HealthBrandTitle() }
                    ToolbarItem(placement: .topBarTrailing) {
                        if isRingBusy || isRefreshingSummary {
                            ProgressView().accessibilityLabel("Updating data")
                        } else {
                            Button("History", systemImage: "calendar") { showAllDays = true }
                                .disabled(s?.days.isEmpty ?? true)
                        }
                    }
                }
            }
            .tabItem { Label("Home", systemImage: "house") }
            .tag(0)

            HealthRingHub(device: s?.device, ring: ring, modules: modules,
                          onConnect: openConnection, onModules: { showModules = true })
                .tabItem {
                    Label { Text("Ring") } icon: { Image(uiImage: HealthRingSymbol.image) }
                }
                .tag(1)

            HealthSettingsView(appearance: $appearance, onProfile: { showProfile = true },
                               onRing: { selectTab(1) }, onModules: { showModules = true })
                .tabItem { Label("Settings", systemImage: "gearshape") }
                .tag(2)
        }
        .environmentObject(ringMotion)
        .environment(\.healthRingSection, selectedTab)
        .overlayPreferenceValue(HealthRingAnchors.self) { anchors in
            HealthRingFlightOverlay(motion: ringMotion, anchors: anchors)
        }
        .modifier(HealthNativeTabBehavior())
        .onChange(of: reduceMotion) { _, reduced in if reduced { ringMotion.cancel() } }
        .onReceive(ring.$busy.removeDuplicates()) { isRingBusy = $0 }
        .tint(sectionAccent)
        .preferredColorScheme(colorScheme)
        .environment(\.locale, Locale(identifier: "en_US"))
        .onChange(of: modules.ouraEnabled) { _, enabled in
            if enabled { requestAutomaticSync() }
            else { if ring.busy { ring.pause() }; showSync = false }
        }
        .fullScreenCover(item: $report) { sel in if let s { DayReportView(s: s, day: sel.day, tab: sel.sleep ? .sleep : .activity) } }
        .sheet(isPresented: $showAllDays) { if let s { AllDaysView(s: s) } }
        .onAppear(perform: applyLaunchArguments)
        .sheet(isPresented: $showSync) {
            if modules.ouraEnabled {
                SyncView(ring: ring, onSynced: refreshAfterSync, onReset: resetAndReload)
            }
        }
        .sheet(isPresented: $showProfile) { ProfileSettingsView(profile: s?.profile, onSaved: refreshDerivedData) }
        .sheet(isPresented: $showModules, onDismiss: {
            if connectAfterModules { connectAfterModules = false; openConnection() }
        }) {
            ModulesView(store: modules, onConnect: { connectAfterModules = true; showModules = false })
        }
        .sheet(isPresented: $showSleepDebt) { if let debt = s?.sleepDebt { SleepDebtDetail(debt: debt) } }
        .sheet(item: $vital) { kind in if let s { VitalTrendView(s: s, kind: kind) } }
        #if TORCH
        .environment(\.dayAnalysis, DayAnalysisContext(summary: s,
            isBusy: isRefreshingSummary || isRingBusy, refresh: refreshDayAnalysis))
        #endif
        .task {
            guard !hasHydratedSummary else { return }
            // Reading/decoding a large JSON cache must not block the first frame.
            let cached = await Task.detached(priority: .userInitiated) { SummaryCache.load() }.value
            if s == nil, let cached { s = cached }
            hasHydratedSummary = true
            requestAutomaticSync()
        }
        .onChange(of: isRefreshingSummary) { _, refreshing in
            if !refreshing, pendingAutomaticRefresh {
                pendingAutomaticRefresh = false
                requestAutomaticSync()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.protectedDataDidBecomeAvailableNotification)) { _ in
            requestAutomaticSync()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                requestAutomaticSync()
            } else if phase == .background {
                ringMotion.cancel()
                WorkCoordinator.shared.invalidateAnalysis()
            }
        }
    }

    private func selectTab(_ tab: Int) {
        ringMotion.begin(from: selectedTab, to: tab, reducedMotion: reduceMotion)
        selectedTab = tab
    }

    // re-read the DB after a sync brought in new events
    private func reload() {
        load(force: true, clearCurrent: true)
    }

    private func resetAndReload() {
        summaryRefresh.invalidate()
        SummaryCache.clear()
        #if TORCH
        ModelCacheStore.clearAll()
        #endif
        reload()
    }

    /// Profile changes affect CVA and activity inference, but do not invalidate the
    /// summary already on screen. Keep the last complete result visible until every
    /// derived model has finished, avoiding a transient sleep-debt regression.
    private func refreshDerivedData() {
        load(force: true, clearCurrent: false)
    }

    /// New ring events invalidate every derived view. In particular this reruns AAD
    /// after the database transaction has completed, so newly accumulated movement
    /// cannot leave yesterday's activity sessions cached on screen.
    private func refreshAfterSync(_ report: SyncReport) {
        guard report.inserted > 0 else { return }
        load(force: true, clearCurrent: false)
    }

    private func requestAutomaticSync() {
        guard ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil,
              hasHydratedSummary, WorkCoordinator.shared.available, !automaticSyncInFlight else { return }
        guard !isRefreshingSummary else { pendingAutomaticRefresh = true; return }
        automaticSyncInFlight = true
        Task {
            defer { automaticSyncInFlight = false }
            let report = modules.ouraEnabled ? await ring.syncAutomaticallyIfNeeded() : nil
            if let report, report.inserted > 0 {
                // New events outrank the freshness window, including when another
                // analysis started while BLE was suspended at the await above.
                summaryRefresh.invalidate()
                if WorkCoordinator.shared.available { refreshAfterSync(report) }
                return
            }
            guard WorkCoordinator.shared.available else { return }
            guard !isRefreshingSummary else { pendingAutomaticRefresh = true; return }
            let now = Date()
            let needsSummary = summaryRefresh.needsRefresh(
                hasSummary: s != nil && s?.error == nil, now: now, day: localDay(now),
                utcOffsetSeconds: TimeZone.current.secondsFromGMT(for: now))
            if needsSummary { load(force: true, clearCurrent: false) }
        }
    }

    private func markSummaryRefreshed() {
        let now = Date()
        summaryRefresh.recordSuccess(now: now, day: localDay(now),
                                     utcOffsetSeconds: TimeZone.current.secondsFromGMT(for: now))
    }

    #if TORCH
    @MainActor private func refreshDayAnalysis(_ request: DayAnalysisRequest) async -> String? {
        guard !isRefreshingSummary, !ring.busy, let previous = s else {
            return "Wait for sync and analysis to finish, then try again."
        }
        guard WorkCoordinator.shared.available else { return "Keep the app open to refresh analysis." }
        let run = WorkCoordinator.shared.newAnalysis()
        loadGeneration += 1
        let generation = loadGeneration
        isRefreshingSummary = true
        modelProgress.begin(generation)
        let progress = modelProgress.sink(generation)
        await WorkGate.shared.acquire()
        guard !run.isCancelled, WorkCoordinator.shared.available else {
            await WorkGate.shared.release()
            WorkCoordinator.shared.finishAnalysis(run)
            if generation == loadGeneration { isRefreshingSummary = false }
            return "Refresh paused. Keep the app open and try again."
        }
        IdleTimerLock.acquire("models")
        dlog("models", "refresh start day=\(request.day) kind=\(request.kind.rawValue) run=\(run.id)")
        let result: (summary: Summary, error: String?) = await withCheckedContinuation { completion in
            DispatchQueue.global(qos: .userInitiated).async {
                completion.resume(returning: run.perform {
                    Core.refreshAnalysis(previous, request: request, progress: progress)
                })
            }
        }
        let canPublish = generation == loadGeneration && !run.isCancelled && WorkCoordinator.shared.available
        if canPublish && result.error == nil {
            markSummaryRefreshed()
            s = result.summary
            SummaryCache.save(result.summary)
            HealthExport.shared.push(result.summary)
        }
        if generation == loadGeneration {
            isRefreshingSummary = false
            modelProgress.report(generation, nil)
        }
        IdleTimerLock.release("models")
        WorkCoordinator.shared.finishAnalysis(run)
        await WorkGate.shared.release()
        dlog("models", "refresh end day=\(request.day) kind=\(request.kind.rawValue) cancelled=\(run.isCancelled)")
        return canPublish ? result.error : "Refresh paused. Keep the app open and try again."
    }
    #endif

    private func load(force: Bool = false, clearCurrent: Bool = false) {
        guard force || s == nil else { return }
        let now = Date()
        summaryRefresh.recordAttempt(now: now, day: localDay(now),
                                     utcOffsetSeconds: TimeZone.current.secondsFromGMT(for: now))
        let run = WorkCoordinator.shared.newAnalysis()
        loadGeneration += 1
        let generation = loadGeneration
        let previous = clearCurrent ? nil : s
        if clearCurrent { s = nil }
        isRefreshingSummary = true
        modelProgress.begin(generation)
        let progress = modelProgress.sink(generation)
        Task {
            await WorkGate.shared.acquire()
            guard !run.isCancelled, WorkCoordinator.shared.available else {
                await WorkGate.shared.release()
                WorkCoordinator.shared.finishAnalysis(run)
                if generation == loadGeneration {
                    summaryRefresh.invalidate()
                    isRefreshingSummary = false
                    modelProgress.report(generation, "Analysis paused")
                }
                return
            }
            IdleTimerLock.acquire("models")
            dlog("models", "start run=\(run.id)")
            let started = ProcessInfo.processInfo.systemUptime
            let full: Summary = await withCheckedContinuation { completion in
                DispatchQueue.global(qos: .userInitiated).async {
                    let summary = run.perform {
                        let base = Core.base()
                        #if TORCH
                        return base.error == nil && !run.isCancelled
                            ? Core.withModels(base, previous: previous, progress: progress) : base
                        #else
                        return base
                        #endif
                    }
                    completion.resume(returning: summary)
                }
            }
            if generation == loadGeneration {
                if !run.isCancelled, WorkCoordinator.shared.available {
                    if full.error == nil {
                        markSummaryRefreshed()
                        s = full
                        SummaryCache.save(full)
                        HealthExport.shared.push(full)
                    } else if s == nil { s = full }
                    modelProgress.report(generation, full.error == nil ? nil : "Couldn’t refresh data.")
                } else {
                    summaryRefresh.invalidate()
                    modelProgress.report(generation, "Analysis paused")
                }
                isRefreshingSummary = false
            }
            dlog("models", "end run=\(run.id) cancelled=\(run.isCancelled) duration_ms=\(Int((ProcessInfo.processInfo.systemUptime - started) * 1000))")
            IdleTimerLock.release("models")
            WorkCoordinator.shared.finishAnalysis(run)
            await WorkGate.shared.release()
        }
    }

    @ViewBuilder private func content(_ s: Summary) -> some View {
        let latestTemp = s.nights.first { $0.skin_temp != nil }
        let latestOxygen = s.nights.first { $0.spo2_mean != nil }
        let latestHRVNight = s.nights.first { $0.hrv_ms != nil }
        let latestHRV = s.vitals.hrv.latest ?? latestHRVNight?.hrv_ms
        let latestHR = s.vitals.hr
        let days = s.days
        let hasVitals = latestHR?.latest != nil || latestHRV != nil || s.vitals.rhr.latest != nil || latestTemp != nil || latestOxygen != nil
        List {
            if days.isEmpty && !hasVitals {
                Section {
                    HealthOnboardingCard { selectTab(1) }
                }
                .listRowInsets(EdgeInsets()).listRowBackground(Color.clear)
                Section {
                    Label("Direct Bluetooth · on-device processing", systemImage: "iphone")
                        .font(.footnote).foregroundStyle(Obs.muted)
                    if let error = s.error {
                        DisclosureGroup("Data details") {
                            Text(error).font(.caption).foregroundStyle(Obs.muted)
                        }
                    }
                }
                .listRowBackground(Obs.homeSurface)
            } else {
                if let day = days.first {
                    Section {
                        HealthDayOverview(summary: s, day: day,
                                          onSleep: { report = ReportSel(day: day, sleep: true) },
                                          onActivity: { report = ReportSel(day: day, sleep: false) })
                    }
                    .listRowInsets(EdgeInsets()).listRowBackground(Color.clear)
                }
                if hasVitals {
                    Section("Latest measurements") {
                        if let hr = latestHR?.latest ?? s.vitals.rhr.latest {
                            HealthMetricRow(title: "Heart rate", symbol: "heart", value: f(hr), unit: "bpm",
                                            detail: latestHR.map { latestLabel(date: $0.date, time: $0.hm) } ?? "Nightly minimum") { vital = .heartRate }
                        }
                        if let hrv = latestHRV {
                            HealthMetricRow(title: "Heart rate variability", symbol: "waveform.path.ecg", value: f(hrv), unit: "ms",
                                            detail: s.vitals.hrv.latest == nil ? latestLabel(date: latestHRVNight.flatMap { s.wakeYmd($0) }) : "Nightly HRV") { vital = .hrv }
                        }
                        if let temp = latestTemp?.skin_temp {
                            HealthMetricRow(title: "Skin temperature", symbol: "thermometer.medium", value: String(format: "%.1f", temp), unit: "°C",
                                            detail: latestTemp.map { latestLabel(date: s.wakeYmd($0)) }) { vital = .temp }
                        }
                        if let oxygen = latestOxygen?.spo2_mean {
                            HealthMetricRow(title: "Blood oxygen", symbol: "drop", value: f(oxygen), unit: "%",
                                            detail: latestOxygen.map { latestLabel(date: s.wakeYmd($0)) }) { vital = .oxygen }
                        }
                    }
                    .listRowBackground(Obs.homeSurface)
                }
                if let digest = s.digest {
                    Section("Your day") {
                        Text(digest).font(.subheadline).foregroundStyle(Obs.ink2)
                    }
                    .listRowBackground(Obs.homeSurface)
                }
                if let debt = s.sleepDebt {
                    Section {
                        SleepDebtCard(debt: debt) { showSleepDebt = true }
                    }
                    .listRowInsets(EdgeInsets()).listRowBackground(Color.clear)
                }
                if let radar = s.symptomRadar, radar.available {
                    Section {
                        IllnessCard(illness: radar)
                    }
                    .listRowInsets(EdgeInsets()).listRowBackground(Color.clear)
                }
                if s.cardio?.vascular_age != nil || s.fitness?.vo2max != nil {
                    Section("Cardiovascular health") {
                        if let cv = s.cardio, let age = cv.vascular_age {
                            LabeledContent("Vascular age", value: String(format: "%.1f years", age))
                            if let chronological = cv.chronological_age {
                                LabeledContent("Compared with your age", value: relAge(age - chronological))
                            }
                            if let pwv = cv.pwv_ms {
                                LabeledContent("Pulse wave velocity", value: String(format: "%.2f m/s", pwv))
                            }
                        }
                        if let vo = s.fitness?.vo2max {
                            LabeledContent("Estimated VO₂max", value: String(format: "%.1f ml/kg/min", vo))
                        }
                    }
                    .font(.subheadline).listRowBackground(Obs.homeSurface)
                }
                if !s.modelErrors.isEmpty || !(s.clock?.warnings.isEmpty ?? true) || s.error != nil {
                    Section {
                        DisclosureGroup("Review data") {
                            if let error = s.error { Text(error) }
                            ForEach(s.clock?.warnings ?? [], id: \.self) { Text($0) }
                            ForEach(s.modelErrors, id: \.self) { Text($0) }
                        }
                        .font(.footnote).foregroundStyle(Obs.bad)
                    }
                    .listRowBackground(Obs.homeSurface)
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Obs.paper)
        .environment(\.defaultMinListRowHeight, 52)
    }

}

/// Which build is actually on this phone. A sideloaded app has no App Store version
/// to compare against, and a failed install looks exactly like a successful one — so
/// show the version, when this binary was signed, and when its free-account
/// certificate stops launching (7 days).
struct BuildStamp: View {
    private static let signedAt: Date? = {
        guard let path = Bundle.main.executableURL?.path,
              let attrs = try? FileManager.default.attributesOfItem(atPath: path) else { return nil }
        return attrs[.modificationDate] as? Date
    }()

    private static let stampFormat: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US")
        f.dateFormat = "MMM d HH:mm"
        return f
    }()

    private static let dayFormat: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US")
        f.dateFormat = "MMM d"
        return f
    }()

    private var line: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        var out = "Health by Red \(short) (\(build)) · \(coreVersion())"
        if let signed = Self.signedAt {
            out += " · built \(Self.stampFormat.string(from: signed))"
            if let expiry = Calendar.current.date(byAdding: .day, value: 7, to: signed) {
                let days = Calendar.current.dateComponents([.day], from: Date(), to: expiry).day ?? 0
                out += days < 0
                    ? " · signing expired"
                    : " · signing good to \(Self.dayFormat.string(from: expiry))"
            }
        }
        return out
    }

    var body: some View {
        Text(line)
            .font(Obs.mono(10))
            .foregroundStyle(Obs.ink2)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.top, 6)
            .textSelection(.enabled)
    }
}

@main
struct OuraApp: App {
    init() { DiagStore.shared.bootstrap() }
    var body: some Scene { WindowGroup { RootView() } }
}
