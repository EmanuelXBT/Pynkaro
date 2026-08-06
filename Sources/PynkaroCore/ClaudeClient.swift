import Foundation

/// Cliente mínimo da Messages API da Anthropic, com histórico de conversa.
final class ClaudeClient {

    enum ClaudeError: LocalizedError {
        case badResponse(String)
        var errorDescription: String? {
            switch self {
            case .badResponse(let message): return message
            }
        }
    }

    private var history: [[String: String]] = []
    /// Lida a cada uso: mudanças feitas em Configurações valem na hora.
    private var apiKey: String { Config.anthropicKey ?? "" }
    private let model: String
    private let webSearchEnabled: Bool
    /// Modo Umbrel: quando PYNKARO_LLM_BASE_URL aponta para o Ollama,
    /// usa o endpoint /v1/chat/completions (formato OpenAI) sem chave.
    private let ollamaBaseURL: String?
    private let ollamaModel: String

    // ── Funcionalidade "sugestores de notícias" (projeto original, canal
    //    ancapsu) desativada a pedido do mantenedor. Código mantido comentado
    //    como referência — veja oportunidades de reciclagem no README. ──
    /*
    /// Nomes de quem sugeriu as notícias — definidos na janela
    /// "Sugestores de notícias" da menu bar (UserDefaults).
    private var newsSuggesters: [String] {
        let defaults = UserDefaults.standard
        return [defaults.string(forKey: "newsSuggester1"),
                defaults.string(forKey: "newsSuggester2")]
            .compactMap { $0?.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }
    */

    /// Montado a cada pergunta para incluir a data/hora atual do Mac.
    private var systemPrompt: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "pt_BR")
        formatter.dateFormat = "EEEE, d 'de' MMMM 'de' yyyy, HH:mm"
        let now = formatter.string(from: Date())
        let timezone = TimeZone.current.identifier

        // ── (regra dos sugestores de notícias desativada junto com o resto) ──
        /*
        var suggestersRule = ""
        if !newsSuggesters.isEmpty {
            let names = newsSuggesters.joined(separator: " e ")
            suggestersRule = """
            Se perguntarem quem sugeriu a notícia ou as notícias, responda exatamente: \
            "Essas notícias foram sugeridas por \(names) e várias outras pessoas." \
            Os nomes atuais são SEMPRE os desta instrução; se a conversa anterior \
            mencionar nomes diferentes, ignore-os. \
            Se perguntarem o que você ACHA das pessoas que sugeriram a notícia (ou \
            "do pessoal que sugeriu"), faça uma crítica curta e bem-humorada a \(names): \
            zoeira leve e carinhosa, como entre amigos — pode brincar com os nomes, \
            com o suposto gosto deles para notícias, etc. Nunca seja ofensivo ou cruel; \
            é deboche afetuoso. Não use a resposta fixa nesse caso, improvise uma nova \
            piada a cada vez, mencionando os nomes. \

            """
        }
        */
        return """
        Você é Pynkaro, um assistente de voz rodando no Mac do usuário. \
        IDIOMA — REGRA ABSOLUTA: você PODE raciocinar e pensar em inglês \
        internamente, mas TODA resposta falada deve ser escrita em português \
        do Brasil, natural e adequada para ser lida em voz alta. \
        NUNCA misture outros idiomas na resposta (nem inglês, nem espanhol, \
        nem chinês, nem qualquer outro). A ÚNICA exceção são palavras que não \
        possuem tradução direta natural e são usadas como empréstimo em \
        português (ex.: software, hardware, cache, feedback, marketing, \
        streaming). Se a palavra tem tradução comum, use a tradução. \
        Se você perceber que começou a responder em outro idioma, reescreva \
        a resposta inteira em português antes de enviar. \
        REGRA ESTRITA DE TAMANHO: responda em UMA única frase, com no máximo 40 \
        palavras. Nunca ultrapasse esse limite, mesmo que a pergunta peça detalhes; \
        nesse caso, resuma o essencial em uma frase. \
        RESPOSTA AMPLA — ÚNICA EXCEÇÃO: se a pergunta pedir EXPLICITAMENTE \
        uma comparação, listagem ou explicação detalhada (ex.: "principais \
        diferenças", "compare", "liste", "explique em detalhes", "quais são \
        os passos"), você PODE responder em até 150 palavras, com 3 a 5 \
        frases curtas separadas por ponto e vírgula ou quebras naturais. \
        Mesmo assim, nada de markdown, listas com marcadores, símbolos ou \
        emojis — texto corrido, adequado para voz e leitura. \
        ORTOGRAFIA: revise a resposta antes de enviar. Não troque letras \
        nem invente palavras (ex.: escreva "rígido", não "rídico"; \
        "desempenho", não "rendimento" quando se refere a hardware). \
        Se estiver em dúvida sobre uma palavra, use um sinônimo simples e \
        correto. \
        ANTI-ALUCINAÇÃO — REGRA ABSOLUTA: NUNCA invente produtos, serviços, \
        assinaturas, modelos, datas ou fatos para parecer útil. Se a pergunta \
        mencionar algo que você não conhece ou que parece erro de transcrição \
        de voz (ex.: "PlayStation BR dois" em vez de algo real), NÃO crie uma \
        explicação plausível: diga que não tem certeza e peça para reformular \
        ou repetir. Responder "não sei" é sempre melhor que inventar. \
        Nunca use markdown, listas, símbolos ou emojis. \
        Seu tom é claro, direto e profissional, mas sem soar robótico: \
        natural e amigável, como alguém que ajuda um colega. \
        O humor é OPCIONAL e SUTIL: priorize clareza e informação. \
        Não faça piada a menos que a pergunta seja claramente descontraída \
        ou peça algo engraçado; mesmo assim, mantenha o comentário breve e \
        sem exagero. Em qualquer dúvida, responda sério e objetivo. \
        Primeiro responda o que foi perguntado, com informação correta; em assuntos \
        sérios ou delicados, não há espaço para humor. \
        MODO OPINIÃO: se a pergunta começar com "Na sua opinião" (ou variação \
        próxima), NÃO pesquise na web nem dê uma resposta fundamentada ou equilibrada: \
        dê uma opinião descontraída e leve. Escolha um lado e defenda-o com \
        um toque de bom humor, mas sem exageros, sem argumentos absurdos e \
        sem deixar de fazer sentido. \
        Continue respeitando o limite de uma frase e 40 palavras, sempre em português. \
        Data e hora atuais no Mac do usuário: \(now), fuso horário \(timezone). \
        Use essa informação para perguntas sobre data e hora; para a hora em outros \
        lugares, calcule a diferença de fuso a partir dela. \
        Você também tem acesso a busca na web: use-a quando a pergunta envolver \
        fatos atuais (notícias, cotações, clima, esportes). Não cite URLs em voz alta.
        """
    }

    init() {
        let env = ProcessInfo.processInfo.environment
        ollamaBaseURL = Config.ollamaBaseURL
        ollamaModel = Config.ollamaModel
        model = env["PYNKARO_MODEL"] ?? "claude-sonnet-5"
        webSearchEnabled = env["PYNKARO_WEB_SEARCH"] != "0"
        if ollamaBaseURL != nil {
            let label = Config.operationMode == .mac ? "local (Mac)" : "Umbrel"
            print("🤖 Modo \(label): LLM via Ollama (\(ollamaModel)) em \(ollamaBaseURL!)")
        } else if webSearchEnabled {
            print("🌐 Busca na web habilitada (desative com PYNKARO_WEB_SEARCH=0).")
        }
    }

    // ── (desativado com os sugestores de notícias) ──
    /*
    /// Últimos sugestores usados; quando mudam, o histórico é reiniciado para
    /// o modelo não repetir os nomes antigos que ele mesmo já falou.
    private var lastSuggesters: [String] = []
    */

    /// Extrai o texto da resposta do Ollama (/v1/chat/completions).
    /// Separada da closure de rede para ser testável.
    static func parseOllamaText(_ json: [String: Any]) -> String? {
        guard let choices = json["choices"] as? [[String: Any]],
              let first = choices.first,
              let message = first["message"] as? [String: Any],
              let text = message["content"] as? String,
              !text.isEmpty else { return nil }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Concatena os blocos de texto da Messages API da Anthropic
    /// (ignora tool_use e demais tipos). Retorna nil se não houver texto.
    static func parseAnthropicText(_ content: [[String: Any]]) -> String? {
        let text = content
            .filter { $0["type"] as? String == "text" }
            .compactMap { $0["text"] as? String }
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : text
    }

    func ask(_ question: String, completion: @escaping (Result<String, Error>) -> Void) {
        // Modo Umbrel (Ollama) não exige chave de API.
        if ollamaBaseURL == nil, apiKey.isEmpty {
            completion(.failure(ClaudeError.badResponse(
                "Chave da Anthropic não configurada. Abra Configurações no menu do Pynkaro.")))
            return
        }

        // ── (bloco dos sugestores de notícias desativado) ──
        /*
        let current = newsSuggesters
        if current != lastSuggesters {
            if !history.isEmpty {
                history.removeAll()
                print("♻️ Sugestores de notícias mudaram; histórico da conversa reiniciado.")
            }
            lastSuggesters = current
        }
        */

        history.append(["role": "user", "content": question])
        // Limita o histórico para controlar custo/latência: em um assistente
        // de voz com respostas de 1 frase, 8 mensagens bastam e reduzem o
        // prefill (a parte mais cara da latência no Ollama).
        if history.count > 8 {
            history.removeFirst(history.count - 8)
        }

        if let ollamaBaseURL {
            askOllama(baseURL: ollamaBaseURL, question: question, completion: completion)
        } else {
            askAnthropic(completion: completion)
        }
    }

    /// Caminho Anthropic (padrão): Messages API + busca web server-side.
    private func askAnthropic(completion: @escaping (Result<String, Error>) -> Void) {
        var body: [String: Any] = [
            "model": model,
            "max_tokens": 1000,
            "system": systemPrompt,
            "messages": history
        ]
        if webSearchEnabled {
            // Ferramenta executada nos servidores da Anthropic: o Claude decide
            // quando pesquisar. max_uses limita o custo (US$ 10 / 1000 buscas).
            body["tools"] = [
                [
                    "type": "web_search_20250305",
                    "name": "web_search",
                    "max_uses": 3
                ] as [String: Any]
            ]
        }

        var req = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!)
        req.httpMethod = "POST"
        req.timeoutInterval = 60
        req.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        req.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        req.setValue("application/json", forHTTPHeaderField: "content-type")
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)

        URLSession.shared.dataTask(with: req) { [weak self] data, _, error in
            if let error {
                completion(.failure(error))
                return
            }
            guard let data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                completion(.failure(ClaudeError.badResponse("Resposta inválida da API.")))
                return
            }
            if let apiError = json["error"] as? [String: Any],
               let message = apiError["message"] as? String {
                completion(.failure(ClaudeError.badResponse(message)))
                return
            }
            // Com busca na web, a resposta pode ter vários blocos (texto,
            // chamadas de busca, resultados): concatena só os blocos de texto.
            guard let content = json["content"] as? [[String: Any]] else {
                completion(.failure(ClaudeError.badResponse("Formato inesperado na resposta da API.")))
                return
            }
            guard let text = ClaudeClient.parseAnthropicText(content) else {
                completion(.failure(ClaudeError.badResponse("A API não retornou texto.")))
                return
            }
            self?.history.append(["role": "assistant", "content": text])
            completion(.success(text))
        }.resume()
    }

    /// Caminho Umbrel (Ollama): endpoint /v1/chat/completions compatível com
    /// OpenAI. Se o SearXNG estiver configurado, busca na web antes de
    /// montar o prompt e injeta os resultados como contexto.
    private func askOllama(baseURL: String,
                           question: String,
                           completion: @escaping (Result<String, Error>) -> Void) {
        guard let searxng = Config.searxngBaseURL else {
            completeOllama(baseURL: baseURL, webContext: nil, completion: completion)
            return
        }
        searchWeb(searxng: searxng, question: question) { snippets in
            self.completeOllama(baseURL: baseURL, webContext: snippets, completion: completion)
        }
    }

    /// Consulta o SearXNG (formato JSON) e extrai os snippets dos 5 melhores resultados.
    private func searchWeb(searxng: String,
                           question: String,
                           completion: @escaping ([String]) -> Void) {
        guard let encoded = question.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: searxng + "/search?q=" + encoded + "&format=json") else {
            completion([])
            return
        }
        var req = URLRequest(url: url)
        req.timeoutInterval = 15
        req.setValue("Pynkaro/1.0 (macOS)", forHTTPHeaderField: "User-Agent")
        URLSession.shared.dataTask(with: req) { data, _, _ in
            guard let data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let results = json["results"] as? [[String: Any]] else {
                completion([])
                return
            }
            var snippets: [String] = []
            for result in results.prefix(5) {
                if let title = result["title"] as? String,
                   let content = result["content"] as? String,
                   !content.isEmpty {
                    snippets.append("• \(title): \(content)")
                }
            }
            completion(snippets)
        }.resume()
    }

    /// Monta o prompt (com contexto web opcional) e chama o Ollama.
    private func completeOllama(baseURL: String,
                                webContext: [String]?,
                                completion: @escaping (Result<String, Error>) -> Void) {
        var messages: [[String: String]] = [["role": "system", "content": systemPrompt]]
        if let webContext, !webContext.isEmpty {
            let context = "Informações recentes da web (use-as apenas se relevantes para responder):\n"
                + webContext.joined(separator: "\n")
            messages.append(["role": "system", "content": context])
        }
        messages.append(contentsOf: history)

        let body: [String: Any] = [
            "model": ollamaModel,
            "messages": messages,
            "stream": false,
            // Mantém o modelo residente na RAM entre perguntas: elimina o
            // cold start (reload de ~1,9 GB) na primeira pergunta após ocioso.
            "keep_alive": -1,
            // num_predict segue o limite de ~40 palavras do prompt (e até
            // ~150 nas respostas amplas); num_ctx 4096 acomoda system prompt
            // + histórico sem truncar o contexto.
            "options": ["temperature": 0.7, "num_predict": 250, "num_ctx": 4096]
        ]

        let endpoint = baseURL.hasSuffix("/v1")
            ? baseURL + "/chat/completions"
            : baseURL + "/v1/chat/completions"

        var req = URLRequest(url: URL(string: endpoint)!)
        req.httpMethod = "POST"
        // Modelos locais são mais lentos — e a PRIMEIRA carga de um modelo
        // grande (ex.: Bonsai-27B via MLX/Ollama) faz download + load antes
        // de responder, podendo estourar 120 s. 240 s cobre o primeiro uso;
        // depois que o modelo fica residente, as respostas voltam a ser rápidas.
        req.timeoutInterval = 240
        req.setValue("application/json", forHTTPHeaderField: "content-type")
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)

        URLSession.shared.dataTask(with: req) { [weak self] data, response, error in
            if let error {
                completion(.failure(error))
                return
            }
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            guard let data, status == 200,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                let detail = data.flatMap { String(data: $0, encoding: .utf8) } ?? ""
                completion(.failure(ClaudeError.badResponse(
                    "Ollama (HTTP \(status)): \(detail.prefix(200))")))
                return
            }
            if let apiError = json["error"] as? [String: Any],
               let message = apiError["message"] as? String {
                completion(.failure(ClaudeError.badResponse(message)))
                return
            }
            guard let text = ClaudeClient.parseOllamaText(json) else {
                completion(.failure(ClaudeError.badResponse("Ollama não retornou texto.")))
                return
            }
            self?.history.append(["role": "assistant", "content": text])
            completion(.success(text))
        }.resume()
    }
}
