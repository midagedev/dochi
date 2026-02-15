import SwiftUI

/// 설정 > AI > 문서 검색 (RAG) 설정 뷰
struct RAGSettingsView: View {
    var settings: AppSettings
    var documentIndexer: DocumentIndexer?

    var body: some View {
        Form {
            // MARK: - 활성화
            Section {
                Toggle("문서 검색 (RAG) 활성화", isOn: Binding(
                    get: { settings.ragEnabled },
                    set: { settings.ragEnabled = $0 }
                ))

                Text("로컬 문서를 임베딩하여 대화 시 관련 내용을 자동으로 참조합니다")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                SettingsSectionHeader(
                    title: "문서 검색",
                    helpContent: "PDF, Markdown, 텍스트 파일을 벡터 임베딩하여 대화 시 관련 문서를 자동으로 검색합니다. OpenAI API 키가 필요합니다."
                )
            }

            if settings.ragEnabled {
                // MARK: - 임베딩 설정
                Section {
                    HStack {
                        Text("임베딩 프로바이더")
                        Spacer()
                        Text("OpenAI")
                            .foregroundStyle(.secondary)
                    }

                    Picker("임베딩 모델", selection: Binding(
                        get: { settings.ragEmbeddingModel },
                        set: { settings.ragEmbeddingModel = $0 }
                    )) {
                        Text("text-embedding-3-small").tag("text-embedding-3-small")
                        Text("text-embedding-3-large").tag("text-embedding-3-large")
                    }

                    Text("text-embedding-3-small은 빠르고 저렴하며, large는 정확도가 더 높습니다")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } header: {
                    SettingsSectionHeader(
                        title: "임베딩 설정",
                        helpContent: "임베딩 모델은 텍스트를 벡터로 변환합니다. small 모델은 1536차원, large 모델은 3072차원 벡터를 생성합니다."
                    )
                }

                // MARK: - 검색 설정
                Section {
                    Toggle("자동 검색", isOn: Binding(
                        get: { settings.ragAutoSearch },
                        set: { settings.ragAutoSearch = $0 }
                    ))

                    Text("메시지 전송 시 자동으로 관련 문서를 검색하여 컨텍스트에 추가합니다")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Stepper("검색 결과 수: \(settings.ragTopK)건", value: Binding(
                        get: { settings.ragTopK },
                        set: { settings.ragTopK = $0 }
                    ), in: 1...10)

                    HStack {
                        Text("최소 유사도: \(String(format: "%.1f", settings.ragMinSimilarity))")
                        Slider(value: Binding(
                            get: { settings.ragMinSimilarity },
                            set: { settings.ragMinSimilarity = $0 }
                        ), in: 0.1...0.9, step: 0.1)
                    }

                    Text("유사도가 이 값 이상인 결과만 참조합니다 (높을수록 엄격)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } header: {
                    SettingsSectionHeader(
                        title: "검색 설정",
                        helpContent: "검색 결과 수와 최소 유사도를 조절합니다. 결과가 너무 많으면 컨텍스트가 길어지고, 유사도가 낮으면 관련 없는 내용이 포함될 수 있습니다."
                    )
                }

                // MARK: - 청킹 설정
                Section {
                    Stepper("청크 크기: \(settings.ragChunkSize)자", value: Binding(
                        get: { settings.ragChunkSize },
                        set: { settings.ragChunkSize = $0 }
                    ), in: 200...2000, step: 100)

                    Stepper("오버랩: \(settings.ragChunkOverlap)자", value: Binding(
                        get: { settings.ragChunkOverlap },
                        set: { settings.ragChunkOverlap = $0 }
                    ), in: 0...500, step: 50)

                    Text("청크 크기는 문서를 나누는 단위, 오버랩은 연속 청크 간 겹치는 부분입니다")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } header: {
                    SettingsSectionHeader(
                        title: "청킹 설정",
                        helpContent: "문서를 벡터화하기 위해 작은 단위(청크)로 나눕니다. 청크가 작으면 정밀한 검색이 가능하지만 맥락이 부족할 수 있습니다."
                    )
                }

                // MARK: - 문서 통계
                if let indexer = documentIndexer {
                    Section {
                        HStack {
                            Text("인덱싱된 문서")
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text("\(indexer.documents.count)건")
                                .font(.system(.body, design: .monospaced))
                        }

                        let totalChunks = indexer.documents.reduce(0) { $0 + $1.chunkCount }
                        HStack {
                            Text("총 청크 수")
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text("\(totalChunks)건")
                                .font(.system(.body, design: .monospaced))
                        }

                        if case .indexing(let progress, let fileName) = indexer.indexingState {
                            VStack(alignment: .leading, spacing: 4) {
                                ProgressView(value: progress)
                                Text("\(fileName) 인덱싱 중... \(Int(progress * 100))%")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    } header: {
                        Text("문서 통계")
                    }

                    // MARK: - 유지보수
                    Section {
                        Button("전체 재인덱싱") {
                            Task {
                                await indexer.reindexAll()
                            }
                        }
                        .buttonStyle(.bordered)
                        .disabled(indexer.indexingState.isIndexing)

                        Button("인덱스 초기화") {
                            indexer.clearAll()
                        }
                        .buttonStyle(.bordered)
                        .foregroundStyle(.red)
                    } header: {
                        Text("유지보수")
                    }
                }
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}
