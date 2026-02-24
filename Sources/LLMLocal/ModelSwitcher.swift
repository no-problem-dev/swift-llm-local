import Foundation
import LLMLocalClient

/// 読み込み済みモデルを追跡する内部エントリ。
struct LoadedModelEntry: Sendable {
    let spec: ModelSpec
    var lastAccessed: Date
}

/// LRUエビクション戦略で読み込み済みモデルを管理するアクター
///
/// どのモデルが読み込まれているか、最後にアクセスされた時間を追跡します。
/// 最大容量に達した場合、最も最近使用されていないモデルが
/// 新しいモデルの読み込み前にエビクトされます。
///
/// ## 使用例
///
/// ```swift
/// let switcher = ModelSwitcher(backend: mlxBackend, maxLoadedModels: 2)
/// try await switcher.ensureLoaded(ModelPresets.gemma2_2B)
/// ```
///
/// `maxLoadedModels: 1`（デフォルト）の場合、一度に1つのモデルのみ読み込み可能な
/// 現在のシステムと同じ動作になります。バックエンドの `loadModel` が実際のモデル読み込みを
/// 処理し、スイッチャーは LRU 追跡とエビクション判定を管理します。
public actor ModelSwitcher {

    /// 同時に読み込み可能なモデルの最大数。
    public nonisolated let maxLoadedModels: Int

    /// アクセスタイムスタンプ付きの読み込み済みモデルの内部追跡。
    private var loadedModels: [String: LoadedModelEntry] = [:]

    /// モデルの読み込み・アンロードに使用するバックエンド。
    private let backend: any LLMLocalBackend

    /// 新しいモデルスイッチャーを作成します。
    ///
    /// - Parameters:
    ///   - backend: モデルの読み込みとアンロードに使用する推論バックエンド。
    ///   - maxLoadedModels: 同時に読み込み可能なモデルの最大数。デフォルトは `1`。
    public init(backend: any LLMLocalBackend, maxLoadedModels: Int = 1) {
        self.backend = backend
        self.maxLoadedModels = maxLoadedModels
    }

    /// 指定されたモデルが読み込まれていることを保証し、容量超過時は LRU をエビクトします。
    ///
    /// モデルが既に読み込まれている場合、再読み込みせずにアクセス時間を更新します。
    /// キャッシュが容量に達している場合、最も最近使用されていないモデルが
    /// 新しいモデルの読み込み前にエビクトされます。
    ///
    /// - Parameter spec: 読み込むモデル仕様。
    /// - Throws: バックエンドがモデルを読み込めない場合。
    public func ensureLoaded(_ spec: ModelSpec) async throws {
        try await ensureLoaded(spec, progressHandler: { _ in })
    }

    /// 指定されたモデルが読み込まれていることを保証し、ダウンロード進捗を報告します。
    ///
    /// モデルが既に読み込まれている場合、再読み込みせずにアクセス時間を更新します。
    /// キャッシュが容量に達している場合、最も最近使用されていないモデルが
    /// 新しいモデルの読み込み前にエビクトされます。
    ///
    /// - Parameters:
    ///   - spec: 読み込むモデル仕様。
    ///   - progressHandler: ダウンロード進捗の更新時に呼び出されるクロージャ。
    /// - Throws: バックエンドがモデルを読み込めない場合。
    public func ensureLoaded(
        _ spec: ModelSpec,
        progressHandler: @Sendable @escaping (DownloadProgress) -> Void
    ) async throws {
        // If model is already tracked, just update its access time
        if loadedModels[spec.id] != nil {
            loadedModels[spec.id]?.lastAccessed = Date()
            return
        }

        // If at capacity, evict the least recently used model
        if loadedModels.count >= maxLoadedModels {
            await evictLRU()
        }

        // Load the model via backend
        try await backend.loadModel(spec, progressHandler: progressHandler)

        // Track the newly loaded model
        loadedModels[spec.id] = LoadedModelEntry(
            spec: spec,
            lastAccessed: Date()
        )
    }

    /// 現在読み込まれているモデル仕様を最近アクセスされた順に返します。
    ///
    /// - Returns: アクセス時間順（最新が先頭）のモデル仕様配列。
    public func loadedModelSpecs() -> [ModelSpec] {
        loadedModels.values
            .sorted { $0.lastAccessed > $1.lastAccessed }
            .map(\.spec)
    }

    /// 現在読み込まれているモデル数を返します。
    ///
    /// - Returns: 現在追跡中のモデル数。
    public func loadedCount() -> Int {
        loadedModels.count
    }

    /// 特定のモデルをアンロードします。
    ///
    /// モデルが現在バックエンドのアクティブモデルである場合、
    /// バックエンドにもアンロードを要求します。モデルが読み込まれていない場合、
    /// このメソッドは何も行いません。
    ///
    /// - Parameter spec: アンロードするモデル仕様。
    public func unload(_ spec: ModelSpec) async {
        guard loadedModels.removeValue(forKey: spec.id) != nil else {
            return
        }
        // If this is the currently loaded backend model, unload it
        let currentModel = await backend.currentModel
        if currentModel == spec {
            await backend.unloadModel()
        }
    }

    /// すべてのモデルをアンロードします。
    ///
    /// 追跡中のすべてのモデルをクリアし、バックエンドに
    /// 現在読み込まれているモデルのアンロードを要求します。
    public func unloadAll() async {
        loadedModels.removeAll()
        await backend.unloadModel()
    }

    /// 指定されたモデルが現在読み込まれているかどうか。
    ///
    /// - Parameter spec: 確認するモデル仕様。
    /// - Returns: モデルが現在読み込み済みとして追跡されている場合は `true`。
    public func isLoaded(_ spec: ModelSpec) -> Bool {
        loadedModels[spec.id] != nil
    }

    // MARK: - Private

    /// 最も最近使用されていないモデルをキャッシュからエビクトします。
    ///
    /// LRU エントリを追跡から削除し、次のモデルをクリーンに読み込めるよう
    /// バックエンドに現在読み込まれているモデルのアンロードを要求します。
    private func evictLRU() async {
        guard let lruEntry = loadedModels.values.min(by: { $0.lastAccessed < $1.lastAccessed }) else {
            return
        }
        loadedModels.removeValue(forKey: lruEntry.spec.id)
        await backend.unloadModel()
    }
}
