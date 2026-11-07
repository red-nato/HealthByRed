import SwiftUI
import UIKit

/// A locally bundled product render. The illuminated sensors are illustrative.
struct HealthRingIllustration: View {
    enum Variant { case green, red, off }
    var size: CGFloat = 200
    var variant: Variant = .green
    private static func load(_ name: String, fallback: String) -> UIImage? {
        if let image = UIImage(named: name) { return image }
        guard let url = Bundle.main.url(forResource: fallback, withExtension: "png") else { return nil }
        return UIImage(contentsOfFile: url.path)
    }
    private static let green = load("RingProduct", fallback: "ring-product")
    private static let red = load("RingRed", fallback: "ring-red")
    private static let off = load("RingOff", fallback: "ring-off")
    private var product: UIImage? {
        switch variant { case .green: Self.green; case .red: Self.red; case .off: Self.off }
    }
    var body: some View {
        Group {
            if let product {
                Image(uiImage: product).resizable().interpolation(.high).scaledToFit()
            } else {
                HealthRingGlyph().foregroundStyle(Obs.homeAccent)
            }
        }.frame(width: size, height: size).accessibilityHidden(true)
    }
}

/// A static source-to-signal connection; it never implies a live measurement.
private struct HealthSourceTrace: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.width * 0.83, y: 0))
        p.addLine(to: CGPoint(x: rect.width * 0.83, y: rect.height * 0.40))
        p.addQuadCurve(to: CGPoint(x: rect.width * 0.72, y: rect.height),
                       control: CGPoint(x: rect.width * 0.83, y: rect.height))
        p.addLine(to: CGPoint(x: 0, y: rect.height))
        return p
    }
}

/// Sizing uses the actual list row width, independently of screen scale/safe areas.
enum HealthRingGeometry {
    static func homeSize(availableWidth: CGFloat) -> CGFloat {
        min(218, max(0, (availableWidth - 24) * 0.54))
    }
    static func interpolate(from: CGRect, to: CGRect, progress: CGFloat) -> CGRect {
        if progress <= 0 { return from }
        if progress >= 1 { return to }
        let t = progress
        func mix(_ a: CGFloat, _ b: CGFloat) -> CGFloat { a + (b - a) * t }
        return CGRect(x: mix(from.minX, to.minX), y: mix(from.minY, to.minY),
                      width: mix(from.width, to.width), height: mix(from.height, to.height))
    }
}

/// The ring has its own column, so it cannot cover the date or the next row.
private struct HealthRhythmHero<Content: View>: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ViewBuilder let content: () -> Content
    var body: some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 12) {
                content()
                HealthRingPlacement(section: 0, size: 164).frame(maxWidth: .infinity)
            }.padding(.horizontal, 22).padding(.top, 22)
        } else {
            GeometryReader { proxy in
                let ringSize = HealthRingGeometry.homeSize(availableWidth: proxy.size.width)
                HStack(spacing: 0) {
                    content().frame(maxWidth: .infinity, alignment: .leading)
                    HealthRingPlacement(section: 0, size: ringSize)
                        .padding(.trailing, 2)
                }
                .padding(.leading, 22)
                .frame(width: proxy.size.width, height: proxy.size.height)
            }.frame(height: 232)
        }
    }
}

/// One overview, with native progress and direct access to the two day reports.
struct HealthDayOverview: View {
    let summary: Summary
    let day: String
    let onSleep: () -> Void
    let onActivity: () -> Void
    private let night: NightRow?
    init(summary: Summary, day: String, onSleep: @escaping () -> Void, onActivity: @escaping () -> Void) {
        self.summary = summary; self.day = day
        self.onSleep = onSleep; self.onActivity = onActivity
        self.night = summary.night(forDay: day)
    }
    private var score: Double? {
        let value = night?.sleep_score?.score ?? night?.efficiency
        return value?.isFinite == true ? value : nil
    }
    private var scoreTitle: String { night?.sleep_score != nil ? "Sleep score" : "Sleep efficiency" }
    private var duration: String {
        guard let hours = night?.in_bed_h, hours.isFinite else { return "—" }
        let minutes = Int((hours * 60).rounded())
        return "\(minutes / 60)h \(minutes % 60)m"
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HealthRhythmHero {
                VStack(alignment: .leading, spacing: 5) {
                    Text("YOUR RHYTHM").font(.system(size: 10, weight: .semibold)).tracking(1.8)
                        .foregroundStyle(Obs.homeAccent)
                    Text(day).font(.caption2).foregroundStyle(Obs.muted).padding(.bottom, 9)
                    Text(score.map { String(Int($0.rounded())) } ?? "—")
                        .font(.system(size: 62, weight: .light)).tracking(-3).monospacedDigit()
                        .foregroundStyle(Obs.ink)
                    Text(scoreTitle).font(.subheadline.weight(.medium)).foregroundStyle(Obs.ink2)
                        .fixedSize(horizontal: false, vertical: true)
                    ProgressView(value: min(100, max(0, score ?? 0)), total: 100)
                        .tint(Obs.homeAccent).frame(width: 78).padding(.top, 5)
                        .accessibilityLabel(scoreTitle)
                        .accessibilityValue(score.map { "\(Int($0)) out of 100" } ?? "No score")
                    Label("From your ring", systemImage: "arrow.down.left")
                        .font(.caption2).foregroundStyle(Obs.muted).padding(.top, 8)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            HealthSourceTrace().stroke(Obs.homeAccent.opacity(0.35), lineWidth: 0.7)
                .frame(height: 14).padding(.horizontal, 22).padding(.top, -6)
                .accessibilityHidden(true)
            HStack(alignment: .top, spacing: 20) {
                stat("Time in bed", value: duration).frame(maxWidth: .infinity, alignment: .leading)
                stat("Steps", value: summary.activity_daily[day]?.steps.map { Int($0).formatted(.number.locale(Locale(identifier: "en_US"))) } ?? "—")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }.padding(.horizontal, 22).padding(.top, 15)
            HStack {
                Button(action: onSleep) { Label("Sleep", systemImage: "moon") }
                Spacer()
                Button(action: onActivity) { Label("Activity", systemImage: "figure.walk") }
            }
            .font(.subheadline.weight(.medium)).buttonStyle(.borderless).tint(Obs.homeAccent)
            .padding(.horizontal, 22).padding(.vertical, 19)
        }
        .background {
            LinearGradient(colors: [Obs.homeHero, Obs.homeSurface], startPoint: .topTrailing, endPoint: .bottomLeading)
                .clipShape(RoundedRectangle(cornerRadius: 24))
        }
        .overlay(RoundedRectangle(cornerRadius: 24).strokeBorder(Obs.homeAccent.opacity(0.15), lineWidth: 0.7))
    }
    private func stat(_ label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(label).font(.caption).foregroundStyle(Obs.muted)
            Text(value).font(.title3.weight(.medium)).monospacedDigit()
                .lineLimit(1).minimumScaleFactor(0.75)
        }
    }
}

struct HealthOnboardingCard: View {
    let onConnect: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HealthRhythmHero {
                VStack(alignment: .leading, spacing: 16) {
                    Text("YOUR HEALTH, CLOSER").font(.system(size: 10, weight: .semibold))
                        .tracking(1.3).foregroundStyle(Obs.homeAccent)
                    Text("Your rhythm.\nReady to be\nrevealed.")
                        .font(.system(size: 25, weight: .medium)).tracking(-0.7)
                        .foregroundStyle(Obs.ink).fixedSize(horizontal: false, vertical: true)
                }
            }
            Text("Connect your ring to bring sleep, movement and vital signs into focus.")
                .font(.subheadline).foregroundStyle(Obs.ink2).padding(.horizontal, 22)
            Button("Set up my ring", systemImage: "arrow.right", action: onConnect)
                .buttonStyle(.borderedProminent).controlSize(.large)
                .tint(Obs.homeAccent).foregroundStyle(Obs.paper)
                .padding(22)
        }
        .background {
            LinearGradient(colors: [Obs.homeHero, Obs.homeSurface], startPoint: .topTrailing, endPoint: .bottomLeading)
                .clipShape(RoundedRectangle(cornerRadius: 24))
        }
        .overlay(RoundedRectangle(cornerRadius: 24).strokeBorder(Obs.homeAccent.opacity(0.15), lineWidth: 0.7))
    }
}

/// A native list row. Full trends live in the metric report, not four tiny cards.
struct HealthMetricRow: View {
    let title: String
    let symbol: String
    let value: String
    let unit: String
    var detail: String? = nil
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: symbol).foregroundStyle(Obs.homeAccent)
                    .frame(width: 24)
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(.subheadline).foregroundStyle(Obs.ink)
                    if let detail {
                        Text(detail).font(.caption2).foregroundStyle(Obs.muted).lineLimit(1)
                    }
                }
                Spacer(minLength: 8)
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Text(value).font(.title3.weight(.medium)).monospacedDigit()
                    Text(unit).font(.caption).foregroundStyle(Obs.muted)
                }.foregroundStyle(Obs.ink).lineLimit(1)
                Image(systemName: "chevron.right").font(.caption2.weight(.semibold))
                    .foregroundStyle(Obs.muted)
            }
            .padding(.vertical, 5)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title), \(value) \(unit)")
        .accessibilityHint("Open measurement history")
    }
}

// Three product photographs share one short, on-demand transition. The native
// TabView/Form/List remain in charge of navigation, scrolling and interaction.
private struct HealthRingSectionKey: EnvironmentKey {
    static let defaultValue = 0
}
extension EnvironmentValues {
    var healthRingSection: Int {
        get { self[HealthRingSectionKey.self] }
        set { self[HealthRingSectionKey.self] = newValue }
    }
}

struct HealthRingAnchors: PreferenceKey {
    static var defaultValue: [Int: Anchor<CGRect>] = [:]
    static func reduce(value: inout [Int: Anchor<CGRect>], nextValue: () -> [Int: Anchor<CGRect>]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}

private struct HealthRingLayoutSnapshot: Equatable {
    let frames: [Int: CGRect]
    let size: CGSize
}

@MainActor
final class HealthRingMotion: ObservableObject {
    struct Flight {
        let id = UUID()
        let from: Int
        let to: Int
        let source: CGRect
        var destination: CGRect?
    }
    @Published private(set) var flight: Flight?
    @Published private(set) var progress: CGFloat = 0
    private var frames: [Int: CGRect] = [:]
    private var cleanup: Task<Void, Never>?
    private var settlement: Task<Void, Never>?
    var viewport: CGRect = .zero

    func update(_ newFrames: [Int: CGRect], viewport newViewport: CGRect? = nil) {
        if let newViewport, newViewport != viewport {
            cancel()
            frames.removeAll()
            viewport = newViewport
        }
        frames.merge(newFrames, uniquingKeysWith: { _, new in new })
        guard let current = flight, let target = newFrames[current.to] else { return }
        guard isVisible(target) else { cancel(); return }
        if let previous = current.destination {
            // A user scroll or live resize invalidates the measured destination.
            if abs(previous.midX - target.midX) > 0.5 || abs(previous.midY - target.midY) > 0.5 ||
                abs(previous.width - target.width) > 0.5 { cancel() }
            return
        }
        // Let the incoming NavigationStack/Form settle its large title and
        // safe area before starting. Use the latest resolved anchor.
        settlement?.cancel()
        settlement = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(34))
            guard !Task.isCancelled, let self, self.flight?.id == current.id,
                  let destination = self.frames[current.to], self.isVisible(destination) else { return }
            self.flight?.destination = destination
            await Task.yield()
            guard self.flight?.id == current.id else { return }
            withAnimation(.timingCurve(0.22, 0.75, 0.22, 1, duration: 0.70)) {
                self.progress = 1
            }
            // The lifetime starts after layout settles, never at the tab tap.
            self.cleanup?.cancel()
            self.cleanup = Task { @MainActor [weak self] in
                try? await Task.sleep(for: .milliseconds(760))
                guard !Task.isCancelled, self?.flight?.id == current.id else { return }
                self?.cancel()
            }
        }
    }
    private func isVisible(_ rect: CGRect) -> Bool {
        rect.width > 0 && rect.height > 0 && viewport.intersects(rect)
    }
    func begin(from: Int, to: Int, reducedMotion: Bool) {
        cancel()
        guard from != to, !reducedMotion, let source = frames[from], isVisible(source) else { return }
        progress = 0
        flight = Flight(from: from, to: to, source: source)
        // Never leave a hidden destination behind if a tab isn't laid out.
        cleanup = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(950))
            guard !Task.isCancelled else { return }
            self?.cancel()
        }
    }
    func cancel() {
        cleanup?.cancel(); cleanup = nil
        settlement?.cancel(); settlement = nil
        var transaction = Transaction(); transaction.disablesAnimations = true
        withTransaction(transaction) { flight = nil; progress = 0 }
    }
}

struct HealthRingPlacement: View {
    @EnvironmentObject private var motion: HealthRingMotion
    @Environment(\.healthRingSection) private var activeSection
    let section: Int
    var size: CGFloat = 218
    static func angle(_ section: Int) -> Double { section == 0 ? -12 : section == 2 ? 8 : 0 }
    static func variant(_ section: Int) -> HealthRingIllustration.Variant {
        section == 0 ? .red : section == 1 ? .green : .off
    }
    var body: some View {
        // The anchor belongs to an untransformed square. Rotation is applied
        // only to the artwork, so the animation doesn't measure a rotated bbox.
        Color.clear.frame(width: size, height: size)
            .overlay {
                HealthRingIllustration(size: size, variant: Self.variant(section))
                    .rotationEffect(.degrees(Self.angle(section)))
                    .opacity(motion.flight == nil ? 1 : 0)
            }
            .anchorPreference(key: HealthRingAnchors.self, value: .bounds) {
                activeSection == section ? [section: $0] : [:]
            }
            .accessibilityHidden(true).allowsHitTesting(false)
    }
}

private struct HealthRingFlightFrame: View, Animatable {
    let flight: HealthRingMotion.Flight
    var progress: CGFloat
    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }
    private func mix(_ a: CGFloat, _ b: CGFloat) -> CGFloat { a + (b - a) * progress }
    var body: some View {
        let target = flight.destination ?? flight.source
        let rect = HealthRingGeometry.interpolate(from: flight.source, to: target, progress: progress)
        let size = rect.width
        let turn = sin(Double(progress) * .pi) * (flight.to > flight.from ? 22 : -22)
        ZStack {
            HealthRingIllustration(size: size, variant: HealthRingPlacement.variant(flight.from))
                .opacity(1 - progress)
            HealthRingIllustration(size: size, variant: HealthRingPlacement.variant(flight.to))
                .opacity(progress)
        }
        .rotation3DEffect(.degrees(turn), axis: (x: 0, y: 1, z: 0), perspective: 0.35)
        .rotationEffect(.degrees(mix(HealthRingPlacement.angle(flight.from), HealthRingPlacement.angle(flight.to))))
        .frame(width: rect.width, height: rect.height)
        .position(x: rect.midX, y: rect.midY)
    }
}

struct HealthRingFlightOverlay: View {
    @ObservedObject var motion: HealthRingMotion
    let anchors: [Int: Anchor<CGRect>]
    var body: some View {
        GeometryReader { proxy in
            let layout = HealthRingLayoutSnapshot(frames: anchors.mapValues { proxy[$0] }, size: proxy.size)
            ZStack(alignment: .topLeading) {
                if let flight = motion.flight {
                    HealthRingFlightFrame(flight: flight, progress: motion.progress)
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .topLeading)
            .onChange(of: layout, initial: true) { _, layout in
                motion.update(layout.frames, viewport: CGRect(origin: .zero, size: layout.size))
            }
        }
        .allowsHitTesting(false).accessibilityHidden(true)
    }
}
