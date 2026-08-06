import Foundation
import AVFoundation

/// Converte texto em fala usando o Kokoro TTS rodando na Umbrel
/// (endpoint OpenAI-compatível `/v1/audio/speech` do Kokoro-FastAPI).
/// Em caso de falha, usa a voz do sistema como fallback.
///
/// Modo Umbrel: ativado por `PYNKARO_KOKORO_URL` (ex.: http://umbrel.local:8877).
final class KokoroSpeaker: NSObject, Speaking, AVAudioPlayerDelegate {

    var onMouthLevel: ((Int) -> Void)?

    private let baseURL: String
    private let voice: String
    private let model: String

    /// Fallback local; lazy para só inicializar (e imprimir) se for necessário.
    private lazy var fallback = Speaker()
    private var player: AVAudioPlayer?
    private var completion: (() -> Void)?
    private var meterTimer: Timer?

    /// Sem timestamps por caractere no Kokoro, o lip sync usa a amplitude
    /// do áudio (mesmo mecanismo de fallback do ElevenLabsSpeaker).
    private struct MouthEvent {
        let time: TimeInterval
        let level: Int
    }
    private var mouthEvents: [MouthEvent] = []
    private var mouthEventIndex = 0

    init(baseURL: String) {
        let env = ProcessInfo.processInfo.environment
        self.baseURL = baseURL
        self.voice = env["PYNKARO_KOKORO_VOICE"] ?? Config.kokoroVoice
        self.model = env["PYNKARO_KOKORO_MODEL"] ?? "kokoro"
        super.init()
        let label = Config.operationMode == .mac ? "local (Mac)" : "Umbrel"
        Log.debug("🗣️ Voz: Kokoro (\(label) \(baseURL), voice \(voice))")
    }

    func speak(_ text: String, completion: @escaping () -> Void) {
        self.completion = completion

        // Endpoint OpenAI-compatível do Kokoro-FastAPI.
        let endpoint = baseURL.hasSuffix("/v1")
            ? baseURL + "/audio/speech"
            : baseURL + "/v1/audio/speech"

        var req = URLRequest(url: URL(string: endpoint)!)
        req.httpMethod = "POST"
        req.timeoutInterval = 120  // primeira carga do modelo pode demorar
        req.setValue("application/json", forHTTPHeaderField: "content-type")
        let body: [String: Any] = [
            "model": model,
            "input": text,
            "voice": voice,
            // wav evita o encode/decode mp3 no servidor e no AVAudioPlayer;
            // na LAN o tamanho maior é irrelevante para a latência.
            "response_format": "wav"
        ]
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)

        URLSession.shared.dataTask(with: req) { [weak self] data, response, error in
            DispatchQueue.main.async {
                guard let self else { return }
                let status = (response as? HTTPURLResponse)?.statusCode ?? 0
                guard error == nil, status == 200, let data, !data.isEmpty else {
                    if let error {
                        Log.error("⚠️ Kokoro: \(error.localizedDescription)")
                    } else {
                        let detail = data.flatMap { String(data: $0, encoding: .utf8) } ?? ""
                        Log.error("⚠️ Kokoro (HTTP \(status)): \(detail.prefix(200))")
                    }
                    self.fallbackSpeak(text)
                    return
                }
                self.mouthEvents = []
                self.mouthEventIndex = 0

                do {
                    let player = try AVAudioPlayer(data: data)
                    player.delegate = self
                    player.isMeteringEnabled = true
                    self.player = player
                    player.play()
                    self.startMetering()  // Kokoro: lip sync por amplitude
                } catch {
                    Log.error("⚠️ Kokoro: falha ao tocar o áudio: \(error.localizedDescription)")
                    self.fallbackSpeak(text)
                }
            }
        }.resume()
    }

    // MARK: - Lip sync por amplitude (~30x por segundo)

    private func startMetering() {
        meterTimer?.invalidate()
        meterTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            guard let self, let player = self.player, player.isPlaying else { return }
            player.updateMeters()
            let db = player.averagePower(forChannel: 0) // -160 (silêncio) a 0 dB
            let level: Int
            if db > -18 {
                level = 2
            } else if db > -32 {
                level = 1
            } else {
                level = 0
            }
            self.onMouthLevel?(level)
        }
    }

    private func stopMetering() {
        meterTimer?.invalidate()
        meterTimer = nil
        mouthEvents = []
        mouthEventIndex = 0
        onMouthLevel?(0)
    }

    /// Para a fala imediatamente: para o player, invalida os timers e
    /// dispara o completion (o assistente volta a aguardar).
    func stop() {
        guard player?.isPlaying == true else { return }
        stopMetering()
        player?.stop()
        player = nil
        let callback = completion
        completion = nil
        callback?()
    }

    private func fallbackSpeak(_ text: String) {
        Log.error("   Usando a voz do sistema como fallback.")
        fallback.onMouthLevel = onMouthLevel
        let callback = completion
        completion = nil
        fallback.speak(text) { callback?() }
    }

    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        stopMetering()
        self.player = nil
        let callback = completion
        completion = nil
        callback?()
    }
}
