import Foundation

/// Auto-teste da lógica pura do Pynkaro (sem XCTest, roda sem Xcode):
///
///     swift build -c release
///     ./.build/release/Pynkaro --selftest
///
/// Saída esperada: "✅ SELFTEST OK — N verificações passaram" e exit 0.
/// Em falha: "❌ SELFTEST FALHOU — N falhas" e exit 1.
enum SelfTest {
    static func run() -> Never {
        var passed = 0
        var failures = 0

        func check(_ name: String, _ condition: Bool) {
            if condition {
                passed += 1
                print("✅ \(name)")
            } else {
                failures += 1
                print("❌ \(name)")
            }
        }

        // MARK: Config.inferMode (modos de operação)
        check("inferMode(nil) == .api",
              Config.inferMode(ollamaURL: nil) == .api)
        check("inferMode(localhost) == .mac",
              Config.inferMode(ollamaURL: "http://localhost:11434/v1") == .mac)
        check("inferMode(127.0.0.1) == .mac",
              Config.inferMode(ollamaURL: "http://127.0.0.1:11434/v1") == .mac)
        check("inferMode(IP LAN) == .umbrel",
              Config.inferMode(ollamaURL: "http://192.0.2.1:11434/v1") == .umbrel)
        check("inferMode(umbrel.local) == .umbrel",
              Config.inferMode(ollamaURL: "http://umbrel.local:11434/v1") == .umbrel)

        // MARK: VoiceAssistant.isCancelRequest
        check("isCancelRequest('esquece')", VoiceAssistant.isCancelRequest("esquece"))
        check("isCancelRequest('Esquece')", VoiceAssistant.isCancelRequest("Esquece"))
        check("isCancelRequest('ESQUECA')", VoiceAssistant.isCancelRequest("ESQUECA"))
        check("isCancelRequest('cancela')", VoiceAssistant.isCancelRequest("cancela"))
        check("isCancelRequest('deixa pra la')", VoiceAssistant.isCancelRequest("deixa pra la"))
        check("isCancelRequest('deixa para lá')", VoiceAssistant.isCancelRequest("deixa para lá"))
        check("!isCancelRequest('esqueci meu nome')", !VoiceAssistant.isCancelRequest("esqueci meu nome"))
        check("!isCancelRequest('cancela o som')", !VoiceAssistant.isCancelRequest("cancela o som"))
        check("!isCancelRequest('qual a hora')", !VoiceAssistant.isCancelRequest("qual a hora"))
        check("!isCancelRequest('')", !VoiceAssistant.isCancelRequest(""))

        // MARK: ElevenLabsSpeaker.viseme
        check("viseme(a) == 2", ElevenLabsSpeaker.viseme(for: "a") == 2)
        check("viseme(e) == 1", ElevenLabsSpeaker.viseme(for: "e") == 1)
        check("viseme(o) == 3", ElevenLabsSpeaker.viseme(for: "o") == 3)
        check("viseme(m) == 0", ElevenLabsSpeaker.viseme(for: "m") == 0)
        check("viseme(f) == 4", ElevenLabsSpeaker.viseme(for: "f") == 4)
        check("viseme(v) == 4", ElevenLabsSpeaker.viseme(for: "v") == 4)
        check("viseme(' ') == nil", ElevenLabsSpeaker.viseme(for: " ") == nil)
        check("viseme('!') == nil", ElevenLabsSpeaker.viseme(for: "!") == nil)
        check("viseme('á') == 2", ElevenLabsSpeaker.viseme(for: "á") == 2)

        // MARK: ClaudeClient.parseOllamaText
        let ollamaOK: [String: Any] = [
            "choices": [["message": ["content": "  Resposta de teste  "]]]
        ]
        check("parseOllamaText sucesso (trim)",
              ClaudeClient.parseOllamaText(ollamaOK) == "Resposta de teste")
        check("parseOllamaText choices vazio",
              ClaudeClient.parseOllamaText(["choices": []]) == nil)
        check("parseOllamaText content vazio",
              ClaudeClient.parseOllamaText(["choices": [["message": ["content": ""]]]]) == nil)

        // MARK: ClaudeClient.parseAnthropicText
        let anthropicOK: [[String: Any]] = [
            ["type": "text", "text": "Olá"],
            ["type": "tool_use", "id": "x"],
            ["type": "text", "text": "mundo"]
        ]
        check("parseAnthropicText concatena blocos de texto",
              ClaudeClient.parseAnthropicText(anthropicOK) == "Olá mundo")
        let anthropicVazio: [[String: Any]] = [["type": "tool_use", "id": "x"]]
        check("parseAnthropicText sem texto",
              ClaudeClient.parseAnthropicText(anthropicVazio) == nil)

        // MARK: ClaudeClient.timestampPrefix (cache KV do Ollama)
        let tp = ClaudeClient.timestampPrefix()
        check("timestampPrefix não é vazio", !tp.isEmpty)
        check("timestampPrefix começa com 'Data e hora atuais'",
              tp.hasPrefix("Data e hora atuais"))
        check("timestampPrefix termina com separador",
              tp.hasSuffix(". "))

        // MARK: IntroScript.matches (apresentação pré-definida)
        check("IntroScript('se apresente')", IntroScript.matches("se apresente"))
        check("IntroScript('Se apresente')", IntroScript.matches("Se apresente"))
        check("IntroScript('pode se apresentar?')", IntroScript.matches("pode se apresentar?"))
        check("IntroScript('quem é você')", IntroScript.matches("quem é você"))
        check("IntroScript('qual é o seu nome?')", IntroScript.matches("qual é o seu nome?"))
        check("!IntroScript('que horas são')", !IntroScript.matches("que horas são"))
        check("!IntroScript('toca uma música')", !IntroScript.matches("toca uma música"))
        check("!IntroScript('')", !IntroScript.matches(""))

        // MARK: AvatarWindow.speechRange (rolagem sincronizada com a fala)
        check("speechRange(total:0) vazio",
              AvatarWindow.speechRange(total: 0, fraction: 0.5) == NSRange(location: 0, length: 0))
        check("speechRange início (fração 0)",
              AvatarWindow.speechRange(total: 500, fraction: 0).location == 0)
        check("speechRange avança com a fração",
              AvatarWindow.speechRange(total: 500, fraction: 0.5).location == 220)
        check("speechRange nunca ultrapassa o total",
              AvatarWindow.speechRange(total: 500, fraction: 1).location + AvatarWindow.speechRange(total: 500, fraction: 1).length <= 500)
        check("speechRange clampa fração >1",
              AvatarWindow.speechRange(total: 500, fraction: 2).location <= 500)

        // MARK: Config.speechLocale
        let sl = Config.speechLocale
        check("speechLocale não é vazio",
              !sl.isEmpty)
        check("speechLocale tem formato xx-XX",
              sl.contains("-") && sl.split(separator: "-").count == 2)

        // MARK: Config.uiLanguage
        let ul = Config.uiLanguage
        check("uiLanguage é pt, en ou system",
              ul == "pt" || ul == "en" || ul == "system")

        // MARK: Config tuning (num_predict/num_ctx/temperature)
        check("numPredict default >= 100",
              Config.numPredict >= 100)
        check("numCtx default >= 2048",
              Config.numCtx >= 2048)
        check("temperature entre 0 e 1",
              Config.temperature >= 0 && Config.temperature <= 1)

        print("")
        if failures == 0 {
            print("✅ SELFTEST OK — \(passed) verificações passaram")
            exit(0)
        } else {
            print("❌ SELFTEST FALHOU — \(failures) falha(s) de \(passed + failures)")
            exit(1)
        }
    }
}
