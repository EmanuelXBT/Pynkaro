import Foundation

/// Roteiro de apresentação pré-definido do Pynkaro.
///
/// Quando o usuário pede para ele se apresentar ("se apresente",
/// "quem é você"...), o app responde este texto FIXO, sem consultar o
/// LLM — rápido, determinístico e sempre igual (útil para gravar vídeo
/// de demonstração). O texto é maior que o limite de fala curta (>45
/// palavras), então a janela de leitura (AnswerWindow) abre junto.
enum IntroScript {

    /// Texto falado na apresentação. Edite aqui o roteiro do vídeo.
    static let text = """
    Olá! Eu sou o Pynkaro, seu assistente de voz local. Funciono inteiramente na sua casa: minha voz vem do Kokoro, um sistema de síntese de fala em português, e meu raciocínio roda em um modelo de linguagem que vive no seu próprio hardware. Nada do que você me diz sai da sua rede. Estou sempre de prontidão — basta me chamar pela palavra de ativação e fazer sua pergunta. Posso responder sobre o tempo, buscar informações, ajudar com tarefas e, em breve, conversar diretamente com agentes de inteligência artificial para executar comandos no seu servidor. Sou discreto, rápido e não interrompo sua rotina: fico em silêncio até você precisar de mim. Que tal testar? Faça uma pergunta e eu mostro do que sou capaz.
    """

    /// Frases que disparam a apresentação (comparação sem acentos e
    /// maiúsculas; a pergunta só precisa CONTER uma delas).
    private static let triggerPhrases = [
        "se apresente",
        "se apresenta",
        "se apresentar",
        "apresente-se",
        "me apresente",
        "apresente",
        "apresentar",
        "apresentacao",
        "quem e voce",
        "qual e o seu nome",
        "qual e seu nome",
        "como voce se chama",
        "fale sobre voce",
        "me conte sobre voce",
    ]

    /// true se a pergunta pede a apresentação pré-definida.
    /// Estática e sem estado para ser testável (SelfTest).
    static func matches(_ question: String) -> Bool {
        let normalized = question
            .folding(options: [.diacriticInsensitive, .caseInsensitive],
                     locale: Locale(identifier: "pt_BR"))
            .lowercased()
        return triggerPhrases.contains { normalized.contains($0) }
    }
}
