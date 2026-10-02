import XCTest
@testable import KeynestCore

final class QuotaClientTests: XCTestCase {
    private let secret = "test-secret-never-send-to-real-service"
    private let deepseek = #"{"is_available":true,"balance_infos":[{"currency":"CNY","total_balance":"110.00100","granted_balance":"10.00100","topped_up_balance":"100.00"}]}"#
    private let siliconflow = #"{"code":20000,"status":true,"data":{"totalBalance":"88.88","balance":"0.88","chargeBalance":"88.00","email":"private@example.test"}}"#
    private let openrouter = #"{"data":{"limit":100,"limit_remaining":74.5,"usage":25.5,"usage_daily":1.1,"usage_weekly":3.3,"usage_monthly":20.2}}"#

    private func parse(_ json: String, _ provider: QuotaProvider) throws -> QuotaSnapshot {
        try QuotaClient.parse(data: Data(json.utf8), provider: provider)
    }

    private func assertInvalid(_ json: String, _ provider: QuotaProvider, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertThrowsError(try parse(json, provider), file: file, line: line) { error in
            XCTAssertEqual(error as? QuotaError, .invalidResponse, file: file, line: line)
        }
    }

    func testDeepSeekKeepsDecimalPrecisionAndCurrenciesSeparate() throws {
        let json = #"{"is_available":true,"balance_infos":[{"currency":"CNY","total_balance":"110.00100","granted_balance":"10.00100","topped_up_balance":"100.00"},{"currency":"USD","total_balance":"2.1234567890123456789","granted_balance":"0","topped_up_balance":"2.1234567890123456789"}]}"#
        let quota = try parse(json, .deepseek)
        XCTAssertEqual(quota.kind, "balance")
        XCTAssertEqual(quota.metrics.count, 6)
        XCTAssertEqual(quota.metrics[0].value, "110.00100")
        XCTAssertEqual(quota.metrics[3].value, "2.1234567890123456789")
        XCTAssertEqual(quota.metrics[3].currency, "USD")
        XCTAssertLessThan(abs(quota.fetchedAt.timeIntervalSinceNow), 5)
    }

    func testUnavailableStatusDoesNotReplaceBalance() throws {
        let quota = try parse(deepseek.replacingOccurrences(of: ":true", with: ":false"), .deepseek)
        XCTAssertTrue(quota.note.contains("余额不足"))
        XCTAssertEqual(quota.metrics[0].value, "110.00100")
    }

    func testSiliconFlowOnlyRetainsTotalBalance() throws {
        let quota = try parse(siliconflow, .siliconflow)
        XCTAssertEqual(quota.metrics, [QuotaMetric(label: "账户总余额", value: "88.88", currency: "CNY")])
        let serialized = try JSONEncoder().encode(quota)
        XCTAssertFalse(String(decoding: serialized, as: UTF8.self).contains("private@example.test"))
    }

    func testOpenRouterLimitIsNotAccountBalance() throws {
        let quota = try parse(openrouter, .openrouter)
        XCTAssertEqual(quota.kind, "key_limit")
        XCTAssertEqual(quota.metrics[0].label, "Key 限额剩余")
        XCTAssertEqual(quota.metrics[0].value, "74.5")
        XCTAssertTrue(quota.note.contains("不是账户余额"))
    }

    func testNullKeyLimitMeansNoCapNotUnlimitedBalance() throws {
        let json = openrouter.replacingOccurrences(of: "\"limit\":100", with: "\"limit\":null")
            .replacingOccurrences(of: "\"limit_remaining\":74.5", with: "\"limit_remaining\":null")
        let quota = try parse(json, .openrouter)
        XCTAssertNil(quota.metrics[0].value)
        XCTAssertNil(quota.metrics[1].value)
        XCTAssertEqual(quota.metrics[0].label, "未设置 Key 上限")
        XCTAssertTrue(quota.note.contains("仍受实际余额限制"))
    }

    func testZeroAndNegativeRemainingAreNotMissingValues() throws {
        let sf = try parse(siliconflow.replacingOccurrences(of: "88.88", with: "0"), .siliconflow)
        XCTAssertEqual(sf.metrics[0].value, "0")
        let or = try parse(openrouter.replacingOccurrences(of: "74.5", with: "-0.01"), .openrouter)
        XCTAssertEqual(or.metrics[0].value, "-0.01")
    }

    func testRequiredFieldsAndStrictTypes() {
        assertInvalid("null", .deepseek)
        assertInvalid(deepseek.replacingOccurrences(of: ":true", with: ":1"), .deepseek)
        assertInvalid(deepseek.replacingOccurrences(of: "\"110.00100\"", with: "110.001"), .deepseek)
        assertInvalid(deepseek.replacingOccurrences(of: "\"CNY\"", with: "\"XYZ\""), .deepseek)
        assertInvalid(deepseek.replacingOccurrences(of: "granted_balance", with: "missing"), .deepseek)
        assertInvalid(deepseek.replacingOccurrences(of: "110.00100", with: "NaN"), .deepseek)
        assertInvalid(deepseek.replacingOccurrences(of: "110.00100", with: "1\\n"), .deepseek)
        assertInvalid(#"{"is_available":true,"balance_infos":[]}"#, .deepseek)
        assertInvalid(siliconflow.replacingOccurrences(of: "totalBalance", with: "missing"), .siliconflow)
        assertInvalid(siliconflow.replacingOccurrences(of: "\"88.88\"", with: "null"), .siliconflow)
        assertInvalid(siliconflow.replacingOccurrences(of: "20000", with: "20012"), .siliconflow)
        assertInvalid(siliconflow.replacingOccurrences(of: ":true", with: ":false"), .siliconflow)
        assertInvalid(openrouter.replacingOccurrences(of: "limit_remaining", with: "missing"), .openrouter)
        assertInvalid(openrouter.replacingOccurrences(of: "74.5", with: "\"74.5\""), .openrouter)
        assertInvalid(openrouter.replacingOccurrences(of: "74.5", with: "true"), .openrouter)
        assertInvalid(openrouter.replacingOccurrences(of: "74.5", with: "1e999"), .openrouter)
        assertInvalid(openrouter.replacingOccurrences(of: "\"limit\":100", with: "\"limit\":null"), .openrouter)
        assertInvalid(openrouter.replacingOccurrences(of: "\"usage\":25.5", with: "\"usage\":-1"), .openrouter)
        assertInvalid(openrouter.replacingOccurrences(of: "usage_monthly", with: "missing"), .openrouter)
    }

    func testDuplicateCurrencyIsRejected() {
        let item = #"{"currency":"CNY","total_balance":"1","granted_balance":"0","topped_up_balance":"1"}"#
        assertInvalid("{\"is_available\":true,\"balance_infos\":[\(item),\(item)]}", .deepseek)
    }

    func testOversizeAndMalformedDataProduceSafeErrors() throws {
        XCTAssertThrowsError(try QuotaClient.parse(data: Data(repeating: 0x20, count: 1_048_577), provider: .deepseek)) {
            XCTAssertEqual($0 as? QuotaError, .responseTooLarge)
        }
        XCTAssertThrowsError(try parse("invalid json \(secret)", .deepseek)) {
            XCTAssertEqual($0 as? QuotaError, .invalidResponse)
            XCTAssertFalse($0.localizedDescription.contains(self.secret))
        }
        XCTAssertThrowsError(try QuotaClient.parse(data: Data([0xc0, 0xaf]), provider: .deepseek)) {
            XCTAssertEqual($0 as? QuotaError, .invalidResponse)
        }
    }

    func testRequestUsesOnlyFixedOfficialEndpoints() throws {
        for (provider, url) in [(QuotaProvider.deepseek, "https://api.deepseek.com/user/balance"), (.siliconflow, "https://api.siliconflow.cn/v1/user/info"), (.openrouter, "https://openrouter.ai/api/v1/key")] {
            let request = try QuotaClient.request(for: SecretEntry(secret: secret, quotaProvider: provider))
            XCTAssertEqual(request.url?.absoluteString, url)
            XCTAssertEqual(request.httpMethod, "GET")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer \(secret)")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Accept"), "application/json")
            XCTAssertEqual(request.timeoutInterval, 10)
            XCTAssertFalse(request.httpShouldHandleCookies)
            XCTAssertEqual(request.cachePolicy, .reloadIgnoringLocalCacheData)
        }
    }

    func testMatchingOfficialOriginAllowsV1BasePathButNeverUsesItAsRequest() throws {
        let entry = SecretEntry(secret: secret, baseURL: "https://api.deepseek.com:443/v1", quotaProvider: .deepseek)
        XCTAssertEqual(try QuotaClient.request(for: entry).url?.absoluteString, "https://api.deepseek.com/user/balance")
    }

    func testOriginMismatchAndCredentialsRejectedBeforeNetwork() {
        for baseURL in ["https://proxy.example/v1", "http://api.deepseek.com", "https://api.deepseek.com:444/v1", "https://api.deepseek.com.evil.test", "https://api.deepseek.com@evil.test", "https://user@api.deepseek.com", "https://api.deepseek.com?key=x", "https://api.deepseek.com#fragment", "not a url"] {
            XCTAssertThrowsError(try QuotaClient.request(for: SecretEntry(secret: secret, baseURL: baseURL, quotaProvider: .deepseek))) {
                XCTAssertEqual($0 as? QuotaError, .originMismatch)
                XCTAssertFalse($0.localizedDescription.contains(self.secret))
            }
        }
        for invalidSecret in ["", "has space", "has\rline", "has\nline", "has\0null", String(repeating: "x", count: 8193)] {
            XCTAssertThrowsError(try QuotaClient.request(for: SecretEntry(secret: invalidSecret, quotaProvider: .deepseek))) {
                XCTAssertEqual($0 as? QuotaError, .invalidSecret)
            }
        }
    }

    func testUnsupportedProviderDoesNotCreateRequest() {
        XCTAssertThrowsError(try QuotaClient.request(for: SecretEntry(secret: secret))) {
            XCTAssertEqual($0 as? QuotaError, .unsupportedProvider)
        }
    }

    func testEphemeralSessionHasNoPersistentCookiesCacheOrCredentials() {
        let config = QuotaClient.configuration()
        XCTAssertNil(config.urlCache)
        XCTAssertNil(config.httpCookieStorage)
        XCTAssertNil(config.urlCredentialStorage)
        XCTAssertFalse(config.httpShouldSetCookies)
        XCTAssertEqual(config.timeoutIntervalForRequest, 10)
        XCTAssertEqual(config.timeoutIntervalForResource, 10)
    }

    func testRedirectDelegateNeverForwardsAnyRequest() throws {
        let url = try XCTUnwrap(URL(string: "https://api.deepseek.com/user/balance"))
        let session = URLSession(configuration: .ephemeral)
        defer { session.invalidateAndCancel() }
        let task = session.dataTask(with: url) // Intentionally never resumed.
        for code in [301, 302, 303, 307, 308] {
            for location in ["https://evil.test/", "https://api.deepseek.com/another-path", "http://api.deepseek.com/user/balance"] {
                let destination = try XCTUnwrap(URL(string: location))
                let response = try XCTUnwrap(HTTPURLResponse(url: url, statusCode: code, httpVersion: nil, headerFields: ["Location": location]))
                var redirect = URLRequest(url: destination)
                redirect.setValue("Bearer \(secret)", forHTTPHeaderField: "Authorization")
                var callbackInvoked = false
                RejectQuotaRedirects().urlSession(session, task: task, willPerformHTTPRedirection: response, newRequest: redirect) {
                    callbackInvoked = true
                    XCTAssertNil($0)
                }
                XCTAssertTrue(callbackInvoked)
            }
        }
    }
}
