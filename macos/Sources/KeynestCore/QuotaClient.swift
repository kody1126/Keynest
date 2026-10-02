import Foundation

/// Only fixed, safe messages are exposed outside the quota adapter.
public enum QuotaError: Error, LocalizedError, Equatable, Sendable {
    case unsupportedProvider, invalidSecret, originMismatch, redirectRejected
    case authentication, rateLimited, upstream, invalidResponse, responseTooLarge
    case timedOut, network, cancelled

    public var errorDescription: String? {
        switch self {
        case .unsupportedProvider: return "此条目未启用额度查询。"
        case .invalidSecret: return "密钥格式无效，请检查后重试。"
        case .originMismatch: return "API 地址与所选额度服务不一致，未发送密钥。"
        case .redirectRejected: return "服务商返回重定向，已拒绝转发密钥。"
        case .authentication: return "密钥无效或无权查询，请检查服务商与密钥。"
        case .rateLimited: return "服务商限制了查询频率，请稍后重试。"
        case .upstream: return "服务商暂时无法完成额度查询，请稍后重试。"
        case .invalidResponse: return "服务商返回的数据格式不符合预期，未更新额度。"
        case .responseTooLarge: return "服务商响应超过 1 MiB，已停止读取。"
        case .timedOut: return "额度查询超过 10 秒，已停止请求。"
        case .network: return "额度查询失败，请检查网络连接及服务商状态。"
        case .cancelled: return "额度查询已取消。"
        }
    }
}

public enum QuotaClient {
    static let maximumResponseBytes = 1_048_576
    static let timeout: TimeInterval = 10

    // Public references checked 2026-09-23:
    // https://api-docs.deepseek.com/api/get-user-balance/
    // https://github.com/siliconflow/siliconcloud/blob/main/openapi.yaml
    // https://openrouter.ai/docs/api_reference/limits
    public static func fetch(entry: SecretEntry) async throws -> QuotaSnapshot {
        let request = try request(for: entry)
        let provider = entry.quotaProvider
        do {
            try Task.checkCancellation()
            return try await withThrowingTaskGroup(of: QuotaSnapshot.self) { group in
                group.addTask { try await download(request: request, provider: provider) }
                group.addTask {
                    try await Task.sleep(nanoseconds: 10_000_000_000)
                    throw QuotaError.timedOut
                }
                defer { group.cancelAll() }
                guard let snapshot = try await group.next() else { throw QuotaError.network }
                return snapshot
            }
        } catch let error as QuotaError {
            throw error
        } catch is CancellationError {
            throw QuotaError.cancelled
        } catch let error as URLError where error.code == .timedOut {
            throw QuotaError.timedOut
        } catch let error as URLError where error.code == .cancelled {
            throw QuotaError.cancelled
        } catch {
            // Never forward localizedDescription, URLs, headers, or server bodies.
            throw QuotaError.network
        }
    }

    static func request(for entry: SecretEntry) throws -> URLRequest {
        guard entry.quotaProvider != .none, let endpoint = entry.quotaProvider.endpoint,
              let official = URLComponents(url: endpoint, resolvingAgainstBaseURL: false),
              official.scheme == "https", let officialHost = official.host else {
            throw QuotaError.unsupportedProvider
        }
        guard !entry.secret.isEmpty, entry.secret.utf8.count <= 8192,
              !entry.secret.unicodeScalars.contains(where: {
                  CharacterSet.whitespacesAndNewlines.contains($0) || CharacterSet.controlCharacters.contains($0)
              }) else { throw QuotaError.invalidSecret }

        if !entry.baseURL.isEmpty {
            guard let supplied = URLComponents(string: entry.baseURL), supplied.url != nil,
                  supplied.scheme?.lowercased() == "https",
                  supplied.host?.lowercased() == officialHost.lowercased(),
                  (supplied.port ?? 443) == (official.port ?? 443),
                  supplied.user == nil, supplied.password == nil,
                  supplied.query == nil, supplied.fragment == nil else {
                throw QuotaError.originMismatch
            }
        }
        var request = URLRequest(url: endpoint, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: timeout)
        request.httpMethod = "GET"
        request.setValue("Bearer \(entry.secret)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpShouldHandleCookies = false
        return request
    }

    static func configuration() -> URLSessionConfiguration {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = timeout
        configuration.timeoutIntervalForResource = timeout
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.urlCredentialStorage = nil
        return configuration
    }

    private static func download(request: URLRequest, provider: QuotaProvider) async throws -> QuotaSnapshot {
        try Task.checkCancellation()
        let session = URLSession(configuration: configuration(), delegate: RejectQuotaRedirects(), delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        let (bytes, response) = try await session.bytes(for: request)
        try Task.checkCancellation()
        guard let response = response as? HTTPURLResponse else { throw QuotaError.invalidResponse }
        guard response.url == request.url else { throw QuotaError.redirectRejected }
        if (300..<400).contains(response.statusCode) { throw QuotaError.redirectRejected }
        if response.statusCode == 401 || response.statusCode == 403 { throw QuotaError.authentication }
        if response.statusCode == 429 { throw QuotaError.rateLimited }
        guard (200..<300).contains(response.statusCode) else { throw QuotaError.upstream }
        guard response.expectedContentLength <= Int64(maximumResponseBytes) else { throw QuotaError.responseTooLarge }
        var data = Data()
        data.reserveCapacity(min(maximumResponseBytes, max(0, Int(response.expectedContentLength))))
        for try await byte in bytes {
            try Task.checkCancellation()
            guard data.count < maximumResponseBytes else { throw QuotaError.responseTooLarge }
            data.append(byte)
        }
        try Task.checkCancellation()
        return try parse(data: data, provider: provider)
    }

    static func parse(data: Data, provider: QuotaProvider) throws -> QuotaSnapshot {
        guard data.count <= maximumResponseBytes else { throw QuotaError.responseTooLarge }
        let decoder = JSONDecoder()
        do {
            switch provider {
            case .none: throw QuotaError.unsupportedProvider
            case .deepseek:
                let response = try decoder.decode(DeepSeekResponse.self, from: data)
                guard (1...2).contains(response.balance_infos.count) else { throw QuotaError.invalidResponse }
                var currencies = Set<String>()
                var metrics: [QuotaMetric] = []
                for info in response.balance_infos {
                    guard ["CNY", "USD"].contains(info.currency), currencies.insert(info.currency).inserted else { throw QuotaError.invalidResponse }
                    metrics += [
                        QuotaMetric(label: "账户总余额", value: try decimal(info.total_balance), currency: info.currency),
                        QuotaMetric(label: "赠送余额", value: try decimal(info.granted_balance), currency: info.currency),
                        QuotaMetric(label: "充值余额", value: try decimal(info.topped_up_balance), currency: info.currency)
                    ]
                }
                return QuotaSnapshot(kind: "balance", metrics: metrics, note: response.is_available
                    ? "账户余额快照；不同币种分别展示。"
                    : "服务商报告当前账户余额不足，无法调用 API。")
            case .siliconflow:
                let response = try decoder.decode(SiliconFlowResponse.self, from: data)
                guard response.code == 20000, response.status else { throw QuotaError.invalidResponse }
                return QuotaSnapshot(kind: "balance", metrics: [
                    QuotaMetric(label: "账户总余额", value: try decimal(response.data.totalBalance), currency: "CNY")
                ], note: "硅基流动中国站账户总余额快照。")
            case .openrouter:
                let info = try decoder.decode(OpenRouterResponse.self, from: data).data
                guard (info.limit.amount == nil) == (info.limit_remaining.amount == nil) else { throw QuotaError.invalidResponse }
                let remaining = info.limit_remaining.amount?.text
                let limit = try info.limit.amount?.nonnegativeText()
                return QuotaSnapshot(kind: "key_limit", metrics: [
                    QuotaMetric(label: remaining == nil ? "未设置 Key 上限" : "Key 限额剩余", value: remaining, currency: "USD"),
                    QuotaMetric(label: "Key 消费上限", value: limit, currency: "USD"),
                    QuotaMetric(label: "累计消费", value: try info.usage.nonnegativeText(), currency: "USD"),
                    QuotaMetric(label: "今日消费（UTC）", value: try info.usage_daily.nonnegativeText(), currency: "USD"),
                    QuotaMetric(label: "本周消费（UTC）", value: try info.usage_weekly.nonnegativeText(), currency: "USD"),
                    QuotaMetric(label: "本月消费（UTC）", value: try info.usage_monthly.nonnegativeText(), currency: "USD")
                ], note: remaining == nil
                    ? "未设置 Key 上限；账户仍受实际余额限制。此接口不返回账户余额。"
                    : "此处为单个 Key 的消费限额，不是账户余额；正在处理的请求可能尚未结算。")
            }
        } catch let error as QuotaError {
            throw error
        } catch {
            throw QuotaError.invalidResponse
        }
    }

    private static func decimal(_ value: String) throws -> String {
        guard value.utf8.count <= 128,
              value.range(of: "\\A-?[0-9]+(?:\\.[0-9]+)?\\z", options: .regularExpression) != nil else {
            throw QuotaError.invalidResponse
        }
        return value
    }
}

final class RejectQuotaRedirects: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest,
                    completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}

private struct DeepSeekResponse: Decodable {
    let is_available: Bool
    let balance_infos: [Balance]
    struct Balance: Decodable {
        let currency: String
        let total_balance: String
        let granted_balance: String
        let topped_up_balance: String
    }
}

private struct SiliconFlowResponse: Decodable {
    let code: Int
    let status: Bool
    let data: Balance
    struct Balance: Decodable { let totalBalance: String }
}

private struct OpenRouterResponse: Decodable {
    let data: KeyInfo
    struct KeyInfo: Decodable {
        let limit: NullableAmount
        let limit_remaining: NullableAmount
        let usage: Amount
        let usage_daily: Amount
        let usage_weekly: Amount
        let usage_monthly: Amount
    }
}

private struct NullableAmount: Decodable {
    let amount: Amount?
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        amount = container.decodeNil() ? nil : try container.decode(Amount.self)
    }
}

private struct Amount: Decodable {
    let value: Decimal
    var text: String { NSDecimalNumber(decimal: value).stringValue }
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        // The Double check rejects strings, booleans and non-finite numbers.
        guard try container.decode(Double.self).isFinite else { throw QuotaError.invalidResponse }
        value = try container.decode(Decimal.self)
        guard !value.isNaN else { throw QuotaError.invalidResponse }
    }
    func nonnegativeText() throws -> String {
        guard value >= 0 else { throw QuotaError.invalidResponse }
        return text
    }
}
