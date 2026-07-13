//
//  MaintenanceView.swift — MacTuner
//
import SwiftUI
import AppKit
import IOKit
import IOKit.ps
import Darwin

// MARK: - Vue : Maintenance

@MainActor
final class MaintenanceModel: ObservableObject {
    @Published var running: String?
    @Published var done = Set<String>()

    func run(_ action: MaintenanceAction) {
        running = action.id
        Task.detached {
            action.run()
            await MainActor.run {
                self.running = nil
                self.done.insert(action.id)
            }
        }
    }
}

struct MaintenanceView: View {
    @StateObject private var model = MaintenanceModel()
    @EnvironmentObject var loc: L10n

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 10), count: 4)

    var body: some View {
        VStack(spacing: 0) {
            TabHeader(icon: "wrench.and.screwdriver.fill",
                      title: loc.t("maint.title"),
                      subtitle: loc.t("maint.subtitle")) { EmptyView() }
            Divider()
            ScrollView {
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(Maintenance.actions) { action in
                        card(action)
                    }
                }
                .tabContent()
            }
            .background(MTColor.fond)
        }
    }

    private func card(_ action: MaintenanceAction) -> some View {
        let done = model.done.contains(action.id)
        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                Image(systemName: action.icon).font(.title3)
                    .foregroundStyle(MTColor.mac).frame(width: 22, alignment: .leading)
                Spacer()
                if action.needsAdmin {
                    Image(systemName: "lock.fill").font(.system(size: 10)).foregroundStyle(.purple)
                }
                if done {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                        .transition(.scale(scale: 0.4).combined(with: .opacity))
                }
            }
            Text(loc.t(action.nameKey)).font(.subheadline.weight(.semibold)).lineLimit(1)
            Text(loc.t(action.whatKey)).font(.caption2).foregroundStyle(.secondary)
                .lineLimit(2, reservesSpace: true)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            HStack {
                Spacer()
                if model.running == action.id {
                    ProgressView().controlSize(.small)
                } else {
                    Button(loc.t("common.run")) {
                        withAnimation(.spring(response: 0.4, dampingFraction: 0.6)) { model.run(action) }
                    }
                    .buttonStyle(DarkButton())
                    .controlSize(.small)
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: 132, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(MTColor.carte))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(MTColor.ligne, lineWidth: 1))
        .animation(.spring(response: 0.4, dampingFraction: 0.6), value: done)
    }
}

