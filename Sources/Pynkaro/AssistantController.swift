import Foundation
import Combine

/// Estado do assistente exposto para a interface (ícone e menu).
enum AssistantStatus: Equatable {
    case starting
    case waiting
    case listening
    case thinking
    case speaking
    case paused

    var symbolName: String {
        switch self {
        case .starting:  return "hourglass"
        case .waiting:   return "ear"
        case .listening: return "waveform"
        case .thinking:  return "ellipsis.bubble"
        case .speaking:  return "speaker.wave.2.fill"
        case .paused:    return "pause.circle"
        }
    }

    var label: String {
        switch self {
        case .starting:  return "Aguardando configuração…"
        case .waiting:   return "Aguardando \"Píncaro\""
        case .listening: return "Ouvindo…"
        case .thinking:  return "Pensando…"
        case .speaking:  return "Falando…"
        case .paused:    return "Escuta pausada"
        }
    }
}

/// Ponte entre o VoiceAssistant (AppKit/GCD) e a interface SwiftUI.
/// O assistente só é criado quando start() é chamado — depois do onboarding,
/// para que a escolha de voz (ElevenLabs ou sistema) veja as chaves salvas.
final class AssistantController: ObservableObject {
    static let shared = AssistantController()

    @Published private(set) var status: AssistantStatus = .starting
    var isPaused: Bool { status == .paused }
    var isRunning: Bool { assistant != nil }

    private var assistant: VoiceAssistant?

    private init() {}

    func start() {
        guard assistant == nil else { return }
        let newAssistant = VoiceAssistant()
        newAssistant.onStatusChange = { [weak self] status in
            DispatchQueue.main.async { self?.status = status }
        }
        assistant = newAssistant
        newAssistant.start()
    }

    func togglePause() {
        guard let assistant else { return }
        if isPaused {
            assistant.resume()
        } else {
            assistant.pause()
        }
    }
}
