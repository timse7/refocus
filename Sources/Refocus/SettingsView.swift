import AppKit
import ServiceManagement
import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettings().tabItem { Label("General", systemImage: "gearshape") }
            ProfilesSettings().tabItem { Label("Profiles", systemImage: "person.2") }
        }
        .frame(width: 560, height: 420)
    }
}

private struct GeneralSettings: View {
    @EnvironmentObject private var store: Store
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var message: String?
    @State private var confirmImport = false

    var body: some View {
        Form {
            Toggle("Launch at login", isOn: $launchAtLogin)
                .onChange(of: launchAtLogin) { _, on in
                    do {
                        if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
                    } catch {
                        message = error.localizedDescription
                        launchAtLogin = SMAppService.mainApp.status == .enabled
                    }
                }
            Toggle("Hide applications", isOn: Binding(get: { !store.config.hidingPaused },
                                                      set: { store.config.hidingPaused = !$0 }))
            LabeledContent("Cycle profiles hotkey") {
                ShortcutRecorder(combo: $store.config.cycleProfilesHotKey)
            }
            LabeledContent("Statistics") {
                Text("\(store.config.totalHidden.formatted()) apps hidden in total")
            }
            Section {
                LabeledContent("Hocus Focus") {
                    Button("Import Settings…") { confirmImport = true }
                        .disabled(!LegacyImporter.isAvailable)
                }
            } footer: {
                Text("Replaces all profiles with the ones from the original Hocus Focus app. Quit Hocus Focus before using Refocus, otherwise both apps hide windows.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .alert("Import Hocus Focus settings?", isPresented: $confirmImport) {
            Button("Import", role: .destructive) {
                do { store.config = try LegacyImporter.load() } catch { message = error.localizedDescription }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Your current Refocus profiles will be replaced.")
        }
        .alert("Something went wrong", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
            Button("OK") {}
        } message: { Text(message ?? "") }
    }
}

private struct ProfilesSettings: View {
    @EnvironmentObject private var store: Store
    @State private var selection: UUID?
    @State private var confirmReset = false

    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                List(selection: $selection) {
                    ForEach(store.config.profiles) { p in
                        HStack {
                            Text(p.name)
                            Spacer()
                            if p.id == store.config.activeProfileID {
                                Image(systemName: "checkmark").foregroundStyle(.tint)
                            }
                        }
                        .tag(p.id)
                    }
                }
                HStack(spacing: 2) {
                    Button { selection = store.addProfile().id } label: { Image(systemName: "plus") }
                        .help("New profile")
                    Button {
                        if let p = store.config.profiles.first(where: { $0.id == selection }) {
                            selection = store.addProfile(copying: p).id
                        }
                    } label: { Image(systemName: "plus.square.on.square") }
                        .help("Duplicate profile")
                        .disabled(selection == nil)
                    Button {
                        if let s = selection { store.deleteProfile(s); selection = store.config.profiles.first?.id }
                    } label: { Image(systemName: "minus") }
                        .help("Delete profile")
                        .disabled(selection == nil || store.config.profiles.count < 2)
                    Spacer()
                }
                .buttonStyle(.borderless)
                .padding(6)
            }
            .frame(width: 170)
            Divider()
            if let id = selection, store.config.profiles.contains(where: { $0.id == id }) {
                ProfileEditor(profileID: id)
            } else {
                Text("Select a profile").foregroundStyle(.secondary).frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .onAppear { selection = selection ?? store.config.activeProfileID }
        .toolbar {
            Button("Reset All Profiles…") { confirmReset = true }
        }
        .alert("Reset all profiles and settings?", isPresented: $confirmReset) {
            Button("Reset", role: .destructive) { store.resetAll(); selection = store.config.activeProfileID }
            Button("Cancel", role: .cancel) {}
        } message: { Text("This can't be undone.") }
    }
}

private struct ProfileEditor: View {
    let profileID: UUID
    @EnvironmentObject private var store: Store
    @State private var editingRule: String?

    private var profile: Profile { store.config.profiles.first { $0.id == profileID }! }

    private func binding<T>(_ key: WritableKeyPath<Profile, T>) -> Binding<T> {
        Binding(get: { profile[keyPath: key] }, set: { v in store.updateProfile(profileID) { $0[keyPath: key] = v } })
    }

    var body: some View {
        Form {
            Section {
                TextField("Name", text: binding(\.name))
                LabeledContent("Default timeout") {
                    HStack {
                        TimeoutSlider(seconds: binding(\.defaultTimeout)).frame(width: 160)
                        Text(TimeoutFormat.describe(profile.defaultTimeout)).monospacedDigit().frame(width: 80, alignment: .leading)
                    }
                }
                Toggle("Hide when focus is lost (default)", isOn: binding(\.defaultHideImmediately))
                if profile.id != store.config.activeProfileID {
                    Button("Make Active") { store.activate(profileID) }
                }
            }
            Section {
                ForEach(profile.rules.keys.sorted { Bundle.appInfo(for: $0).name < Bundle.appInfo(for: $1).name }, id: \.self) { bid in
                    let info = Bundle.appInfo(for: bid)
                    let rule = profile.rules[bid]!
                    VStack(alignment: .leading) {
                        HStack {
                            Image(nsImage: info.icon).resizable().frame(width: 18, height: 18)
                            Text(info.name)
                            Spacer()
                            Text(TimeoutFormat.describe(rule.timeout) + (rule.hideImmediately ? " · on focus loss" : ""))
                                .foregroundStyle(.secondary)
                            Button { editingRule = editingRule == bid ? nil : bid } label: { Image(systemName: "slider.horizontal.3") }
                                .buttonStyle(.borderless)
                            Button { store.setRule(nil, for: bid, in: profileID) } label: { Image(systemName: "trash") }
                                .buttonStyle(.borderless)
                                .help("Remove; the app then follows the profile default")
                        }
                        if editingRule == bid {
                            RuleEditor(bundleID: bid, profileID: profileID)
                        }
                    }
                }
            } header: {
                HStack {
                    Text("Application settings")
                    Spacer()
                    Button("Add App…", action: addApp).buttonStyle(.borderless)
                }
            }
        }
        .formStyle(.grouped)
    }

    private func addApp() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.allowsMultipleSelection = true
        guard panel.runModal() == .OK else { return }
        for url in panel.urls {
            guard let bid = Bundle(url: url)?.bundleIdentifier else { continue }
            if profile.rules[bid] == nil { store.setRule(profile.defaultRule, for: bid, in: profileID) }
            editingRule = bid
        }
    }
}
