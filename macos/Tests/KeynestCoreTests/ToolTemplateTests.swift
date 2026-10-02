import Foundation
import XCTest
@testable import KeynestCore

final class ToolTemplateTests: XCTestCase {
    func testStableCatalogIDsAndKinds() {
        XCTAssertEqual(ToolTemplate.all.map(\.id), [
            "cursor", "cline", "roo-code", "continue", "opencode", "claude-code", "openclaw",
            "dify", "n8n", "flowise", "langgraph", "crewai", "open-webui", "anythingllm",
            "cherry-studio", "web-search-skill", "web-crawl-skill", "voice-assistant", "knowledge-agent",
            "cloudflare-skill", "github-skill", "notion-skill", "email-skill", "map-weather-skill", "browser-skill"
        ])
        XCTAssertEqual(Set(ToolTemplate.all.map(\.id)).count, ToolTemplate.all.count)
        XCTAssertEqual(Set(ToolTemplate.all.map(\.kind)), Set(ToolTemplateKind.allCases))
        XCTAssertEqual(ToolTemplate.all.filter { $0.logoID != nil }.count, 15)
        XCTAssertEqual(ToolTemplate.all.filter { $0.logoID == nil }.count, 10)
    }

    func testCredentialRolesAreBoundedAndDefaultsAreValidAlternatives() throws {
        for template in ToolTemplate.all {
            XCTAssertTrue((1...3).contains(template.credentialSlots.count), template.id)
            XCTAssertEqual(Set(template.credentialSlots.map(\.id)).count, template.credentialSlots.count, template.id)
            XCTAssertTrue(template.credentialSlots.contains { !$0.isOptional }, template.id)
            for slot in template.credentialSlots {
                XCTAssertFalse(slot.id.isEmpty, template.id)
                XCTAssertFalse(slot.title.isEmpty, template.id)
                XCTAssertFalse(slot.providerIDs.isEmpty, template.id)
                XCTAssertEqual(Set(slot.providerIDs).count, slot.providerIDs.count, template.id)
                XCTAssertTrue(slot.providerIDs.contains(slot.defaultProviderID), template.id)
                for id in slot.providerIDs {
                    let preset = try XCTUnwrap(ProviderPreset.match(provider: id))
                    XCTAssertEqual(preset.id, id, template.id)
                    XCTAssertEqual(preset.quotaProvider, .none, template.id)
                }
            }
        }
    }

    func testBrandedAndGenericTemplatesHaveDistinctAuthenticIdentity() throws {
        for template in ToolTemplate.all {
            if let logoID = template.logoID {
                XCTAssertEqual(logoID, template.id)
                XCTAssertEqual(template.iconFilename, "\(logoID).png")
                XCTAssertTrue(template.providerLogoIDs.isEmpty, template.id)
                let url = try XCTUnwrap(URLComponents(string: template.website))
                XCTAssertEqual(url.scheme, "https", template.id)
                XCTAssertFalse(url.host?.isEmpty ?? true, template.id)
                XCTAssertNil(url.user, template.id); XCTAssertNil(url.password, template.id)
                XCTAssertNil(url.query, template.id); XCTAssertNil(url.fragment, template.id)
            } else {
                XCTAssertNil(template.iconFilename, template.id)
                XCTAssertTrue(template.website.isEmpty, template.id)
                XCTAssertTrue((1...3).contains(template.providerLogoIDs.count), template.id)
                let allowed = Set(template.credentialSlots.flatMap(\.providerIDs))
                XCTAssertTrue(Set(template.providerLogoIDs).isSubset(of: allowed), template.id)
                for id in template.providerLogoIDs { XCTAssertNotEqual(ProviderPreset.match(provider: id), nil, template.id) }
            }
        }
    }

    func testNotesFitToolSchemaAndDescribeOnlyOrganization() throws {
        for template in ToolTemplate.all {
            let group = ToolGroup(name: template.name, notes: template.notes)
            XCTAssertEqual(try group.validated(), group, template.id)
            XCTAssertFalse(template.summary.isEmpty, template.id)
            XCTAssertTrue(template.notes.contains("保存并关联凭据"), template.id)
            XCTAssertTrue(template.notes.contains("实际调用在对应工具中配置"), template.id)
        }
    }

    func testExactLookupRejectsUnknownOrUnrelatedIdentifiers() {
        for template in ToolTemplate.all { XCTAssertEqual(ToolTemplate.match(templateID: template.id), template) }
        for unknown in ["", "Cursor", " cursor ", "openai", "../cursor", "https://cursor.com", "sk-fixture-only"] {
            XCTAssertNil(ToolTemplate.match(templateID: unknown))
        }
    }

    func testSearchSupportsBrandsAliasesPurposesAndProviderChoices() throws {
        let roo = try XCTUnwrap(ToolTemplate.match(templateID: "roo-code"))
        XCTAssertTrue(roo.matches(search: "ROOCODE"))
        XCTAssertTrue(roo.matches(search: "Ｒｏｏ　Ｃｏｄｅ"))
        let knowledge = try XCTUnwrap(ToolTemplate.match(templateID: "knowledge-agent"))
        XCTAssertTrue(knowledge.matches(search: "RAG"))
        XCTAssertTrue(knowledge.matches(search: "知识库 pinecone"))
        XCTAssertFalse(knowledge.matches(search: "qdrant unrelated-search-token"))
        let search = try XCTUnwrap(ToolTemplate.match(templateID: "web-search-skill"))
        XCTAssertTrue(search.matches(search: "联网 搜索"))
        for template in ToolTemplate.all {
            XCTAssertTrue(template.matches(search: " \n"))
            XCTAssertFalse(template.matches(search: "!!!"))
            XCTAssertFalse(template.matches(search: "sk-fixture-only-secret"))
        }
    }

    func testDocumentedVariablesAreNeverAppliedToDifferentProviderAlternatives() {
        let expected = ["anthropic": "ANTHROPIC_API_KEY", "brave": "BRAVE_API_KEY", "langsmith": "LANGSMITH_API_KEY"]
        var seen = Set<String>()
        for slot in ToolTemplate.all.flatMap(\.credentialSlots) {
            guard let variable = slot.environmentVariable else { continue }
            XCTAssertEqual(slot.providerIDs.count, 1)
            XCTAssertEqual(expected[slot.defaultProviderID], variable)
            seen.insert(variable)
        }
        XCTAssertEqual(seen, Set(expected.values))
    }

    func testSubscriptionAndLocalModelAlternativesAreNotMisrepresentedAsAPIRequirements() throws {
        let claude = try XCTUnwrap(ToolTemplate.match(templateID: "claude-code"))
        XCTAssertEqual(claude.credentialSlots.count, 1)
        XCTAssertEqual(claude.credentialSlots[0].providerIDs, ["anthropic"])
        XCTAssertTrue(claude.notes.contains("订阅登录"))
        XCTAssertTrue(claude.notes.contains("不需要新增 API 密钥"))
        for id in ["cline", "continue", "opencode", "open-webui", "anythingllm"] {
            let template = try XCTUnwrap(ToolTemplate.match(templateID: id))
            XCTAssertTrue(template.notes.contains("本地"), id)
        }
    }

    func testOptionalCapabilitiesAreSeparateFromTheChosenPrimaryAPI() throws {
        let n8n = try XCTUnwrap(ToolTemplate.match(templateID: "n8n"))
        XCTAssertEqual(n8n.credentialSlots.map(\.defaultProviderID), ["openai", "firecrawl", "resend"])
        XCTAssertEqual(n8n.credentialSlots.map(\.isOptional), [false, true, true])
        let knowledge = try XCTUnwrap(ToolTemplate.match(templateID: "knowledge-agent"))
        let vector = try XCTUnwrap(knowledge.credentialSlots.first { $0.id == "vector-store" })
        XCTAssertEqual(vector.providerIDs, ["qdrant", "pinecone"])
        XCTAssertTrue(vector.isOptional)
        for id in vector.providerIDs {
            XCTAssertTrue(try XCTUnwrap(ProviderPreset.match(provider: id)).baseURL.isEmpty)
        }
        let search = try XCTUnwrap(ToolTemplate.match(templateID: "web-search-skill"))
        XCTAssertEqual(search.credentialSlots.count, 1)
        XCTAssertEqual(search.credentialSlots[0].providerIDs, ["tavily", "brave", "exa"])
        XCTAssertEqual(search.credentialSlots[0].defaultProviderID, "tavily")
    }

    func testKnownTemplatesAndSlotsAreDeterministicIndependentValues() {
        let original = ToolTemplate.all
        var copy = ToolTemplate.all
        copy.removeAll()
        XCTAssertTrue(copy.isEmpty)
        XCTAssertEqual(ToolTemplate.all, original)
        XCTAssertTrue(ToolTemplate.all.allSatisfy { !$0.credentialSlots.isEmpty })
    }

    func testFunctionalSkillsCoverCommonServicesWithoutFakeProductBrands() throws {
        let expected: [String: [String]] = [
            "cloudflare-skill": ["cloudflare"], "github-skill": ["github"], "notion-skill": ["notion"],
            "email-skill": ["resend", "sendgrid"], "map-weather-skill": ["amap", "mapbox", "openweather"],
            "browser-skill": ["browserbase", "browserless"]
        ]
        for (id, providers) in expected {
            let template = try XCTUnwrap(ToolTemplate.match(templateID: id))
            XCTAssertEqual(template.kind, .skill)
            XCTAssertNil(template.logoID)
            XCTAssertEqual(template.providerLogoIDs, providers)
        }
        let browser = try XCTUnwrap(ToolTemplate.match(templateID: "browser-skill"))
        XCTAssertTrue(browser.notes.contains("Project ID"))
        let maps = try XCTUnwrap(ToolTemplate.match(templateID: "map-weather-skill"))
        XCTAssertEqual(maps.credentialSlots.map(\.isOptional), [false, true])
    }
}
