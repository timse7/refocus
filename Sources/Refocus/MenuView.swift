import AppKit
import SwiftUI

struct MenuView: View {
    @EnvironmentObject private var store: Store
    @EnvironmentObject private var engine: HidingEngine
    @Environment(\.openSettings) private var openSettings
    @State private var expanded: String?

    private var sections: [(String, [AppRow])] {
        var visible: [AppRow] = [], hidden: [AppRow] = [], disabled: [AppRow] = []
        for r in engine.rows {
            switch r.state {
            case .active, .counting, .offscreen: visible.append(r)
            case .hidden: hidden.append(r)
            case .disabled: disabled.append(r)
            }
        }
        return [("Visible", visible), ("Hidden", hidden), ("Disabled", disabled)].filter { !$0.1.isEmpty }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(sections, id: \.0) { title, rows in
                        Text(title.uppercased())
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .padding(.top, 8)
                            .padding(.horizontal, 6)
                        ForEach(rows) { row in
                            AppRowView(row: row, expanded: $expanded)
                        }
                    }
                }
                .padding(.horizontal, 6)
                .padding(.bottom, 6)
            }
            .frame(height: listHeight)
            Divider()
            footer
        }
        .frame(width: 330)
    }

    private var listHeight: CGFloat {
        let rows = engine.rows.count, titles = sections.count
        return min(460, CGFloat(rows) * 28 + CGFloat(titles) * 26 + (expanded == nil ? 8 : 104))
    }

    private var header: some View {
        HStack {
            Picker("Profile", selection: Binding(get: { store.config.activeProfileID },
                                                 set: { store.activate($0) })) {
                ForEach(store.config.profiles) { Text($0.name).tag($0.id) }
            }
            .labelsHidden()
            .fixedSize()
            Spacer()
            Text(store.config.hidingPaused ? "Paused" : "Hiding")
                .font(.callout)
                .foregroundStyle(.secondary)
            Toggle("Hiding enabled", isOn: Binding(get: { !store.config.hidingPaused },
                                                   set: { store.config.hidingPaused = !$0 }))
                .toggleStyle(.switch)
                .controlSize(.small)
                .labelsHidden()
        }
        .padding(10)
    }

    private var footer: some View {
        HStack {
            Text("\(store.config.totalHidden.formatted()) apps hidden")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Button {
                openSettings()
                NSApp.activate()
            } label: { Image(systemName: "gearshape") }
                .help("Settings…")
            Button { NSApp.terminate(nil) } label: { Image(systemName: "power") }
                .help("Quit Refocus")
        }
        .buttonStyle(.borderless)
        .padding(10)
    }
}

private struct AppRowView: View {
    let row: AppRow
    @Binding var expanded: String?
    @EnvironmentObject private var store: Store
    @State private var hovering = false

    private var isExpanded: Bool { expanded == row.bundleID }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Image(nsImage: row.icon).resizable().frame(width: 18, height: 18)
                Text(row.name).lineLimit(1)
                if row.isCustom {
                    Circle().fill(.tint).frame(width: 5, height: 5).help("Custom setting in this profile")
                }
                Spacer()
                status
            }
            .padding(.horizontal, 6)
            .frame(height: 26)
            .background(RoundedRectangle(cornerRadius: 5)
                .fill(hovering || isExpanded ? Color.primary.opacity(0.08) : .clear))
            .contentShape(Rectangle())
            .onHover { hovering = $0 }
            .onTapGesture {
                withAnimation(.easeOut(duration: 0.15)) { expanded = isExpanded ? nil : row.bundleID }
            }
            if isExpanded {
                RuleEditor(bundleID: row.bundleID, profileID: store.activeProfile.id)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
            }
        }
    }

    @ViewBuilder private var status: some View {
        switch row.state {
        case .active:
            Text("active").foregroundStyle(.green)
        case .counting(let t):
            Text(TimeoutFormat.countdown(t)).monospacedDigit().foregroundStyle(.secondary)
        case .offscreen:
            Text("—").foregroundStyle(.tertiary).help("No window on this Space")
        case .hidden:
            Button("Show") { row.app.unhide() }.buttonStyle(.borderless).controlSize(.small)
        case .disabled:
            Text("never").foregroundStyle(.tertiary)
        }
    }
}

/// Timeout slider plus "hide when focus is lost" for one app in one profile.
struct RuleEditor: View {
    let bundleID: String
    let profileID: UUID
    @EnvironmentObject private var store: Store

    private var profile: Profile? { store.config.profiles.first { $0.id == profileID } }
    private var rule: AppRule { profile?.rule(for: bundleID) ?? AppRule(timeout: 0, hideImmediately: false) }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Hide after")
                Spacer()
                Text(TimeoutFormat.describe(rule.timeout)).monospacedDigit().foregroundStyle(.secondary)
            }
            TimeoutSlider(seconds: Binding(get: { rule.timeout },
                                           set: { var r = rule; r.timeout = $0; save(r) }))
            HStack {
                Toggle("Hide when focus is lost", isOn: Binding(get: { rule.hideImmediately },
                                                                set: { var r = rule; r.hideImmediately = $0; save(r) }))
                    .disabled(rule.isDisabled)
                Spacer()
                if profile?.rules[bundleID] != nil {
                    Button("Use default") { store.setRule(nil, for: bundleID, in: profileID) }
                        .buttonStyle(.link)
                        .help("Remove the custom setting and follow the profile default")
                }
            }
        }
        .font(.callout)
    }

    private func save(_ r: AppRule) { store.setRule(r, for: bundleID, in: profileID) }
}

struct TimeoutSlider: View {
    @Binding var seconds: Int

    var body: some View {
        Slider(value: Binding(get: { Double(TimeoutFormat.nearestStep(seconds)) },
                              set: { seconds = TimeoutFormat.steps[Int($0.rounded())] }),
               in: 0...Double(TimeoutFormat.steps.count - 1), step: 1)
            .controlSize(.small)
    }
}
