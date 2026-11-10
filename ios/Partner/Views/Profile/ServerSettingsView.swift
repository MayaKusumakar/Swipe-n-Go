import SwiftUI

/// Profile → Server: where the app finds the shared backend.
struct ServerSettingsView: View {
    @Environment(AppStore.self) private var store
    @State private var draftURL = ""
    @State private var testing = false
    @FocusState private var urlFocused: Bool

    var body: some View {
        @Bindable var store = store
        Form {
            Section {
                HStack {
                    Text("Status")
                    Spacer()
                    ServerStatusLabel(status: store.serverStatus)
                }
                if case .offline(let message) = store.serverStatus {
                    Text(message)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            Section {
                TextField("http://192.168.1.20:8080", text: $draftURL)
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .focused($urlFocused)
                    .submitLabel(.go)
                    .onSubmit(applyAndTest)
                Button(action: applyAndTest) {
                    HStack {
                        Text("Save & test connection")
                        if testing { Spacer(); ProgressView() }
                    }
                }
                .disabled(testing)
            } header: {
                Text("Server address")
            } footer: {
                Text("Leave empty to use the app without a server. In the simulator, http://localhost:8080 works. On an iPhone, use your Mac's Wi‑Fi address (System Settings → Wi‑Fi → Details → IP Address) and keep both on the same network.")
            }

            Section {
                Toggle("Show sample events", isOn: $store.showSampleEvents)
            } footer: {
                Text("Sample events are built into the app and only exist on this phone. Turn them off to see only what people actually posted.")
            }

            Section("Run the server on your Mac") {
                Text("cd backend\npython3 -m venv .venv && source .venv/bin/activate\npip install -r requirements.txt\nEVENT_STORE=memory flask --app main run --host 0.0.0.0 --port 8080")
                    .font(.system(.footnote, design: .monospaced))
                    .textSelection(.enabled)
            }
        }
        .navigationTitle("Server")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { draftURL = store.serverURLString }
    }

    private func applyAndTest() {
        urlFocused = false
        store.serverURLString = draftURL.trimmingCharacters(in: .whitespaces)
        testing = true
        Task {
            await store.syncWithServer()
            testing = false
        }
    }
}

struct ServerStatusLabel: View {
    let status: ServerStatus

    var body: some View {
        switch status {
        case .off:
            Label("Off", systemImage: "circle").foregroundStyle(.secondary)
        case .connecting:
            Label("Connecting…", systemImage: "arrow.triangle.2.circlepath").foregroundStyle(.secondary)
        case .online(let count, _):
            Label("Online · \(count) events", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
        case .offline:
            Label("Offline", systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange)
        }
    }
}
