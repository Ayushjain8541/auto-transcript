import Foundation
@preconcurrency import WhisperKit

/// All network operations belong to ModelManager. This adapter only reads local files.
public enum LocalWhisper {
    public static func prepare(_ location: ModelLocation) async throws {
        let engine = try await load(location)
        await engine.unloadModels()
    }
    static func load(_ location: ModelLocation) async throws -> WhisperKit {
        let tokenizer = try await AutoTokenizerWrapper.from(modelFolder: location.tokenizerFolder)
        let engine = try await WhisperKit(WhisperKitConfig(modelFolder: location.modelFolder.path, tokenizerFolder: location.tokenizerFolder, verbose: false, prewarm: false, load: false, download: false))
        // Supplying the tokenizer bypasses the SDK's download-on-error fallback.
        engine.tokenizer = try LocalTokenizer(tokenizer)
        engine.textDecoder.isModelMultilingual = true
        try await engine.loadModels()
        return engine
    }
}

/// English segment transcription does not request word alignment, but token grouping
/// remains valid for UTF-8 fragments and whitespace if the SDK calls it.
private struct LocalTokenizer: WhisperTokenizer {
    let base: TokenizerWrapper
    let specialTokens: SpecialTokens
    let allLanguageTokens: Set<Int>
    init(_ base: TokenizerWrapper) throws {
        func id(_ text: String) throws -> Int {
            guard let result = base.convertTokenToId(text) else { throw ModelFailure.corruptArtifact("tokenizer missing \(text)") }; return result
        }
        self.base = base
        specialTokens = try .init(endToken: id("<|endoftext|>"), englishToken: id("<|en|>"), noSpeechToken: id("<|nospeech|>"), noTimestampsToken: id("<|notimestamps|>"), specialTokenBegin: id("<|endoftext|>"), startOfPreviousToken: id("<|startofprev|>"), startOfTranscriptToken: id("<|startoftranscript|>"), timeTokenBegin: id("<|0.00|>"), transcribeToken: id("<|transcribe|>"), translateToken: id("<|translate|>"), whitespaceToken: id(" "))
        allLanguageTokens = Set(Constants.languages.values.compactMap { base.convertTokenToId("<|\($0)|>") })
    }
    func encode(text: String) -> [Int] { base.encode(text: text) }
    func decode(tokens: [Int]) -> String { base.decode(tokens: tokens) }
    func convertTokenToId(_ token: String) -> Int? { base.convertTokenToId(token) }
    func convertIdToToken(_ id: Int) -> String? { base.convertIdToToken(id) }
    func splitToWordTokens(tokenIds: [Int]) -> (words: [String], wordTokens: [[Int]]) {
        var words: [String] = [], groups: [[Int]] = [], pending: [Int] = []
        for token in tokenIds {
            pending.append(token)
            let text = decode(tokens: pending)
            if text.contains("\u{fffd}") { continue }
            if words.isEmpty || text.first?.isWhitespace == true || token >= specialTokens.specialTokenBegin {
                words.append(text); groups.append(pending)
            } else { words[words.count - 1] += text; groups[groups.count - 1] += pending }
            pending = []
        }
        if !pending.isEmpty { words.append(decode(tokens: pending)); groups.append(pending) }
        return (words, groups)
    }
}
