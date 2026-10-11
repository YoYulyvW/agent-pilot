import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var store: Store
    @State private var relayURL: String = ""
    @State private var deviceName: String = ""
    @State private var barkKey: String = ""
    @State private var fileServerURL: String = ""
    @State private var showSaveToast = false

    var body: some View {
        Form {
            Section {
                ConnectionBadge(state: store.connectionState)
                if let err = store.transport.lastError {
                    Text(err).font(.caption).foregroundStyle(.red)
                }
            } header: {
                Text("连接状态")
            } footer: {
                Text("连接到你自建的中继服务（relay_server.py，默认端口 8860）。未填写时展示演示数据。")
            }

            Section {
                TextField("https://relay.example.com", text: $relayURL)
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                TextField("iPhone", text: $deviceName)
                TextField("Bark 推送 Key（可选）", text: $barkKey)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                TextField("文件服务器地址（可选，大文件上传）", text: $fileServerURL)
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            } header: {
                Text("中继服务")
            } footer: {
                Text("超过 150 KB 的文件需配置文件服务器才能发送；未配置则小文件内联走中继。")
            }

            Section {
                Button("保存并连接") { save() }
                    .frame(maxWidth: .infinity)
                Button("立即重连") { store.reconnect() }
                    .frame(maxWidth: .infinity)
            }

            Section("在线智能体") {
                if store.devices.isEmpty {
                    Text("暂未发现其它设备").font(.subheadline).foregroundStyle(.secondary)
                } else {
                    ForEach(store.devices) { d in
                        HStack {
                            Text(d.deviceName)
                            Spacer()
                            Text(d.platform).font(.caption).foregroundStyle(.secondary)
                            Circle().fill(d.online ? Color.green : Color.gray).frame(width: 8, height: 8)
                        }
                    }
                }
                Button("刷新设备列表") {
                    Task { await store.refreshDevices() }
                }
            }

            Section {
                LabeledContent("版本", value: AppConstants.version)
                LabeledContent("中继协议", value: "relay v1 (poll)")
            } header: {
                Text("关于")
            } footer: {
                Text("本应用为 TrollStore 免签名安装构建，未经过 App Store。")
            }
        }
        .navigationTitle("设置")
        .onAppear {
            relayURL = store.relayURL
            deviceName = store.deviceName
            barkKey = store.barkKey
            fileServerURL = store.fileServerURL
        }
        .alert("已保存", isPresented: $showSaveToast) {
            Button("好", role: .cancel) {}
        }
    }

    private func save() {
        store.relayURL = relayURL.trimmingCharacters(in: .whitespaces)
        store.deviceName = deviceName
        store.barkKey = barkKey
        store.fileServerURL = fileServerURL.trimmingCharacters(in: .whitespaces)
        store.reconnect()
        showSaveToast = true
    }
}
