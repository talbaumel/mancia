/// Keeps one Copilot ACP process alive and one empty session warm.
///
/// The warm session is single-use: once a prompt is sent, the session id is
/// discarded so selected text never carries into a later edit.
actor CopilotACPSidecar {
    static let maximumClients = 3
    private var clients: [CopilotACPConfig: CopilotACPClient] = [:]
    private var warmSessionIDs: [CopilotACPConfig: String] = [:]
    private var recency: [CopilotACPConfig] = []
    /// In-flight client launch, shared by concurrent callers so only one
    /// `copilot --acp` process is ever started per config.
    private var starting: [CopilotACPConfig: Task<CopilotACPClient, Error>] = [:]

    func prepare(config newConfig: CopilotACPConfig) async {
        do {
            _ = try await warmSession(config: newConfig)
        } catch {
            await reset(config: newConfig)
        }
    }

    func complete(_ prompt: String, config newConfig: CopilotACPConfig) async throws -> String {
        do {
            let client = try await client(config: newConfig)
            let sessionID: String
            if let warmSessionID = warmSessionIDs.removeValue(forKey: newConfig) {
                sessionID = warmSessionID
            } else {
                sessionID = try await client.newSession()
            }
            touch(newConfig)
            return try await client.prompt(sessionID: sessionID, text: prompt)
        } catch {
            await reset(config: newConfig)
            throw error
        }
    }

    /// The live model list the CLI advertises. Reuses (or warms) the idle
    /// session rather than consuming it, so asking costs nothing extra.
    func availableModels(config newConfig: CopilotACPConfig) async -> [CopilotModel] {
        do {
            _ = try await warmSession(config: newConfig)
            return await clients[newConfig]?.availableModels() ?? []
        } catch {
            await reset(config: newConfig)
            return []
        }
    }

    private func warmSession(config newConfig: CopilotACPConfig) async throws -> String {
        if let warmSessionID = warmSessionIDs[newConfig] {
            touch(newConfig)
            return warmSessionID
        }
        let client = try await client(config: newConfig)
        let sessionID = try await client.newSession()
        warmSessionIDs[newConfig] = sessionID
        touch(newConfig)
        return sessionID
    }

    /// The client for `newConfig`, launching one if needed.
    ///
    /// Actor isolation does not prevent reentrancy: every `await` here is a
    /// suspension point another caller can interleave at. Two callers arriving
    /// with no client stored — the panel warming while Settings asks for the
    /// model list, say — would each launch a `copilot --acp` process, and the
    /// second assignment would strand the first one running with nothing left
    /// to stop it. So in-flight creation is shared through a stored `Task`
    /// rather than repeated, and the check-then-store below runs with no
    /// `await` between the two, which is what makes it atomic.
    private func client(config newConfig: CopilotACPConfig) async throws -> CopilotACPClient {
        if let client = clients[newConfig] {
            touch(newConfig)
            return client
        }
        if let task = starting[newConfig] { return try await task.value }

        let task = Task {
            return try await CopilotACPClient(config: newConfig)
        }
        starting[newConfig] = task
        defer { starting.removeValue(forKey: newConfig) }
        do {
            let created = try await task.value
            clients[newConfig] = created
            touch(newConfig)
            await evictClientsIfNeeded(keeping: newConfig)
            return created
        } catch {
            throw error
        }
    }

    private func touch(_ config: CopilotACPConfig) {
        recency.removeAll { $0 == config }
        recency.append(config)
    }

    private func evictClientsIfNeeded(keeping config: CopilotACPConfig) async {
        while clients.count > Self.maximumClients,
              let staleConfig = recency.first(where: { $0 != config }) {
            recency.removeAll { $0 == staleConfig }
            warmSessionIDs.removeValue(forKey: staleConfig)
            if let client = clients.removeValue(forKey: staleConfig) {
                await client.stop()
            }
        }
    }

    private func reset(config: CopilotACPConfig) async {
        starting.removeValue(forKey: config)?.cancel()
        warmSessionIDs.removeValue(forKey: config)
        recency.removeAll { $0 == config }
        if let client = clients.removeValue(forKey: config) {
            await client.stop()
        }
    }
}
