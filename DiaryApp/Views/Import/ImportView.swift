// ImportView.swift
// Provides three import paths:
//   1. File picker → JSON / CSV / ZIP
//   2. Plain text paste → TextImporter
//   3. Share extension → App Group queue → app launch import
//
// All paths funnel through ImportManager → store.importEntries().

import SwiftUI
import UniformTypeIdentifiers

struct ImportView: View {
    @EnvironmentObject var store: DiaryStore

    @State private var pastedText = ""
    @State private var showFilePicker = false
    @State private var importResult: ImportResultState? = nil
    @State private var isImporting = false

    enum ImportResultState {
        case success(Int)
        case failure(String)
    }

    // UTTypes accepted by the file picker
    private let acceptedTypes: [UTType] = [
        .json,
        .commaSeparatedText,
        UTType(filenameExtension: "zip") ?? .data,
        .pdf,           // PDF import (stub in MVP)
    ]

    var body: some View {
        NavigationStack {
            Form {
                fileImportSection
                textPasteSection
                futureSection
            }
            .navigationTitle("インポート")
            .fileImporter(
                isPresented: $showFilePicker,
                allowedContentTypes: acceptedTypes,
                allowsMultipleSelection: false
            ) { result in
                handleFileResult(result)
            }
            .alert(resultTitle, isPresented: Binding(
                get: { importResult != nil },
                set: { if !$0 { importResult = nil } }
            )) {
                Button("OK") { importResult = nil }
            } message: {
                Text(resultMessage)
            }
            .overlay {
                if isImporting {
                    ZStack {
                        Color.black.opacity(0.25).ignoresSafeArea()
                        ProgressView("読み込み中…")
                            .padding(20)
                            .background(.ultraThickMaterial)
                            .cornerRadius(12)
                    }
                }
            }
        }
    }

    // MARK: - Sections

    private var fileImportSection: some View {
        Section {
            Button {
                showFilePicker = true
            } label: {
                Label("JSON / CSV / ZIP を選択", systemImage: "folder.badge.plus")
            }
        } header: {
            Text("ファイルから読み込む")
        } footer: {
            Text("JSON・CSV は日記データとしてパースされます。ZIPはJSONまたはCSVを含む場合に対応予定です。")
        }
    }

    private var textPasteSection: some View {
        Section {
            ZStack(alignment: .topLeading) {
                TextEditor(text: $pastedText)
                    .frame(minHeight: 120)
                if pastedText.isEmpty {
                    Text("日記テキストを貼り付け…")
                        .foregroundStyle(.tertiary)
                        .padding(.top, 8)
                        .padding(.leading, 5)
                        .allowsHitTesting(false)
                }
            }
            Button("テキストを取り込む") {
                importPastedText()
            }
            .disabled(pastedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        } header: {
            Text("テキスト貼り付け")
        } footer: {
            Text("「2024-01-15」のような日付行で区切ると、複数の日記エントリとして取り込まれます。")
        }
    }

    private var futureSection: some View {
        Section {
            Label("共有シートからの受け取り（対応済み）", systemImage: "square.and.arrow.up")
                .font(.footnote)
                .foregroundStyle(.secondary)
            Text("他アプリから共有したテキスト・URL・画像は Share Extension 経由で本体アプリに取り込まれます。")
                .font(.footnote)
                .foregroundStyle(.secondary)
            Label("iOSジャーナル・他アプリ専用パーサー（今後対応）", systemImage: "app.badge")
                .font(.footnote)
                .foregroundStyle(.secondary)
        } header: {
            Text("共有・今後の予定")
        }
    }

    // MARK: - Handlers

    private func handleFileResult(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            isImporting = true
            Task {
                defer { isImporting = false }
                let accessed = url.startAccessingSecurityScopedResource()
                defer { if accessed { url.stopAccessingSecurityScopedResource() } }
                do {
                    let entries = try ImportManager.importFile(at: url)
                    store.importEntries(entries)
                    importResult = .success(entries.count)
                } catch {
                    importResult = .failure(error.localizedDescription)
                }
            }
        case .failure(let error):
            importResult = .failure(error.localizedDescription)
        }
    }

    private func importPastedText() {
        isImporting = true
        Task {
            defer { isImporting = false }
            do {
                let entries = try ImportManager.importText(pastedText)
                store.importEntries(entries)
                pastedText = ""
                importResult = .success(entries.count)
            } catch {
                importResult = .failure(error.localizedDescription)
            }
        }
    }

    // MARK: - Alert helpers

    private var resultTitle: String {
        switch importResult {
        case .success: return "取り込み完了"
        case .failure: return "取り込み失敗"
        case nil:      return ""
        }
    }

    private var resultMessage: String {
        switch importResult {
        case .success(let n): return "\(n)件の日記を取り込みました"
        case .failure(let m): return m
        case nil:             return ""
        }
    }
}
