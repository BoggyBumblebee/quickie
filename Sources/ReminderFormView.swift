import SwiftUI

struct ReminderFormView: View {
    @StateObject private var viewModel: ReminderFormViewModel

    init(viewModel: ReminderFormViewModel) {
        _viewModel = StateObject(wrappedValue: viewModel)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 12) {
                Image(nsImage: StatusIcon.image())
                    .resizable()
                    .frame(width: 28, height: 28)
                Text("Quickie")
                    .font(.title2.weight(.semibold))
                Spacer()
            }

            Form {
                TextField("Title", text: $viewModel.draft.title)

                DatePicker("Date", selection: $viewModel.draft.date, displayedComponents: .date)

                DatePicker("Time", selection: $viewModel.draft.time, displayedComponents: .hourAndMinute)

                Toggle("Urgent", isOn: $viewModel.draft.urgent)
                    .toggleStyle(.checkbox)

                if viewModel.showsListPicker {
                    Picker("Organisation / List", selection: Binding(
                        get: { viewModel.selectedListID ?? "" },
                        set: { viewModel.selectedListID = $0.isEmpty ? nil : $0 }
                    )) {
                        ForEach(viewModel.lists) { list in
                            Text(list.name).tag(list.id)
                        }
                    }
                } else {
                    VStack(alignment: .leading, spacing: 8) {
                        if viewModel.isBusy {
                            HStack(spacing: 8) {
                                ProgressView()
                                    .controlSize(.small)
                                Text("Loading your Reminders lists...")
                            }
                        } else if let listLoadingMessage = viewModel.listLoadingMessage {
                            Text(listLoadingMessage)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)

                            if viewModel.canRetryListLoading {
                                Button("Retry") {
                                    Task {
                                        await viewModel.refreshLists()
                                    }
                                }
                                .controlSize(.small)
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }

                TextField("Tags", text: $viewModel.draft.tagsText)
                    .help("Tags are saved as hashtags in the reminder notes.")
            }
            .formStyle(.grouped)

            if let errorMessage = viewModel.errorMessage, !viewModel.canRetryListLoading {
                Text(errorMessage)
                    .font(.callout)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack {
                Button("Cancel") {
                    viewModel.cancel()
                }
                .keyboardShortcut(.cancelAction)

                Spacer()

                Button("Add") {
                    Task {
                        await viewModel.addReminder()
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!viewModel.canAdd)
            }
        }
        .padding(20)
        .frame(width: 392)
        .task {
            await viewModel.loadListsIfNeeded()
        }
    }
}
