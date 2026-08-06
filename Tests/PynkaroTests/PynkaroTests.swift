import XCTest
@testable import PynkaroCore

final class PynkaroCoreTests: XCTestCase {

    // MARK: - Config.inferMode (modos de operação)

    func testInferModeSemURL() {
        XCTAssertEqual(Config.inferMode(ollamaURL: nil), .api)
    }

    func testInferModeLocalhost() {
        XCTAssertEqual(Config.inferMode(ollamaURL: "http://localhost:11434/v1"), .mac)
        XCTAssertEqual(Config.inferMode(ollamaURL: "http://127.0.0.1:11434/v1"), .mac)
    }

    func testInferModeLAN() {
        XCTAssertEqual(Config.inferMode(ollamaURL: "http://192.168.0.189:11434/v1"), .umbrel)
        XCTAssertEqual(Config.inferMode(ollamaURL: "http://umbrel.local:11434/v1"), .umbrel)
    }

    // MARK: - VoiceAssistant.isCancelRequest

    func testIsCancelRequestFrasesCompletas() {
        XCTAssertTrue(VoiceAssistant.isCancelRequest("esquece"))
        XCTAssertTrue(VoiceAssistant.isCancelRequest("Esquece"))
        XCTAssertTrue(VoiceAssistant.isCancelRequest("ESQUECA"))
        XCTAssertTrue(VoiceAssistant.isCancelRequest("cancela"))
        XCTAssertTrue(VoiceAssistant.isCancelRequest("deixa pra la"))
        XCTAssertTrue(VoiceAssistant.isCancelRequest("deixa para lá"))
    }

    func testIsCancelRequestIgnoraFraseMaior() {
        XCTAssertFalse(VoiceAssistant.isCancelRequest("esqueci meu nome"))
        XCTAssertFalse(VoiceAssistant.isCancelRequest("cancela o som"))
        XCTAssertFalse(VoiceAssistant.isCancelRequest("qual a hora"))
        XCTAssertFalse(VoiceAssistant.isCancelRequest(""))
    }

    // MARK: - ElevenLabsSpeaker.viseme

    func testVisemeNiveisDeBoca() {
        XCTAssertEqual(ElevenLabsSpeaker.viseme(for: "a"), 2)
        XCTAssertEqual(ElevenLabsSpeaker.viseme(for: "e"), 1)
        XCTAssertEqual(ElevenLabsSpeaker.viseme(for: "o"), 3)
        XCTAssertEqual(ElevenLabsSpeaker.viseme(for: "m"), 0)
        XCTAssertEqual(ElevenLabsSpeaker.viseme(for: "f"), 4)
        XCTAssertEqual(ElevenLabsSpeaker.viseme(for: "v"), 4)
    }

    func testVisemeIgnoraEspacosEPontuacao() {
        XCTAssertNil(ElevenLabsSpeaker.viseme(for: " "))
        XCTAssertNil(ElevenLabsSpeaker.viseme(for: "!"))
        XCTAssertNil(ElevenLabsSpeaker.viseme(for: "."))
    }

    func testVisemeDiacriticos() {
        XCTAssertEqual(ElevenLabsSpeaker.viseme(for: "á"), 2)
        XCTAssertEqual(ElevenLabsSpeaker.viseme(for: "é"), 1)
    }

    // MARK: - ClaudeClient.parseOllamaText

    func testParseOllamaTextSucesso() {
        let json: [String: Any] = [
            "choices": [["message": ["content": "  Resposta de teste  "]]]
        ]
        XCTAssertEqual(ClaudeClient.parseOllamaText(json), "Resposta de teste")
    }

    func testParseOllamaTextSemConteudo() {
        XCTAssertNil(ClaudeClient.parseOllamaText(["choices": []]))
        XCTAssertNil(ClaudeClient.parseOllamaText(["choices": [["message": ["content": ""]]]]))
        XCTAssertNil(ClaudeClient.parseOllamaText([:]))
    }

    // MARK: - ClaudeClient.parseAnthropicText

    func testParseAnthropicTextConcatenaBlocos() {
        let content: [[String: Any]] = [
            ["type": "text", "text": "Olá"],
            ["type": "tool_use", "id": "x"],
            ["type": "text", "text": "mundo"]
        ]
        XCTAssertEqual(ClaudeClient.parseAnthropicText(content), "Olá mundo")
    }

    func testParseAnthropicTextSemTexto() {
        let content: [[String: Any]] = [["type": "tool_use", "id": "x"]]
        XCTAssertNil(ClaudeClient.parseAnthropicText(content))
        XCTAssertNil(ClaudeClient.parseAnthropicText([]))
    }
}
