import XCTest
@testable import MyGramCore

final class FilterTests: XCTestCase {
    func testConfigLoads() throws {
        let config = try FilterResources.loadConfig()
        XCTAssertFalse(config.groups.isEmpty)
        XCTAssertTrue(try FilterResources.scriptSource().contains("MutationObserver"))
    }

    func testCSSContainsEveryEnabledSelector() throws {
        let config = try FilterResources.loadConfig()
        let css = FilterBuilder.css(config)
        XCTAssertTrue(css.contains("a[href=\"/reels/\"]{display:none!important}"))
        XCTAssertTrue(css.contains(":is(li, [role=\"listitem\"]):has(a[href=\"/reels/\"])"))
        XCTAssertTrue(css.contains("html:not([data-mygram-content]) :is(article):has(a[href*=\"/reel/\"])"))
    }

    func testOptionalGroupOnlyWhenEnabled() throws {
        let config = try FilterResources.loadConfig()
        XCTAssertFalse(FilterBuilder.css(config).contains("liked_by"))
        XCTAssertTrue(FilterBuilder.css(config, enabledOptional: ["counts"]).contains("liked_by"))
    }

    func testContentRuleListIsValidJSONWithSimpleSelectorsOnly() throws {
        let config = try FilterResources.loadConfig()
        let json = try XCTUnwrap(FilterBuilder.contentRuleListJSON(config))
        let rules = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(json.utf8)) as? [[String: Any]])
        XCTAssertEqual(rules.count, 1)
        let action = try XCTUnwrap(rules[0]["action"] as? [String: String])
        XCTAssertEqual(action["type"], "css-display-none")
        let selector = try XCTUnwrap(action["selector"])
        XCTAssertTrue(selector.contains("a[href=\"/reels/\"]"))
        XCTAssertFalse(selector.contains(":has("))
        XCTAssertFalse(selector.contains("article"))
    }

    func testContentRuleListNilWhenNothingToHide() throws {
        let empty = FilterConfig(
            version: 1, allowedHosts: [], homePath: "/", inboxPath: "/", blockedPrefixes: [],
            allowedPrefixes: [], suggestedTexts: [], groups: [], health: [])
        XCTAssertNil(FilterBuilder.contentRuleListJSON(empty))
    }

    func testUserScriptEmbedsParsableConfig() throws {
        let config = try FilterResources.loadConfig()
        let script = FilterBuilder.userScript(config, scriptBody: "/*body*/")
        XCTAssertTrue(script.hasPrefix("window.__mygramConfig = {"))
        XCTAssertTrue(script.hasSuffix("/*body*/"))
        let jsonPart = script.dropFirst("window.__mygramConfig = ".count).prefix { $0 != "\n" }.dropLast()
        let obj = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(jsonPart.utf8)) as? [String: Any])
        XCTAssertNotNil(obj["hide"])
        XCTAssertNotNil(obj["suggestedTexts"])
    }

    func testCSSInjectionScriptEscapesQuotes() {
        let script = FilterBuilder.cssInjectionScript("a[href=\"/x\"]{}\n")
        XCTAssertTrue(script.contains("a[href=\\\"/x\\\"]{}\\n"))
    }

    // MARK: FilterHealth

    func testHealthReportsEmptySelectorsWhenLoggedInOnHome() {
        let report = HealthReport(loggedIn: true, path: "/", counts: ["reelsTab": 0, "exploreTab": 1])
        XCTAssertEqual(FilterHealth.problems(in: report), ["reelsTab"])
    }

    func testHealthIgnoresLoggedOutAndOtherPages() {
        XCTAssertTrue(FilterHealth.problems(in: HealthReport(loggedIn: false, path: "/", counts: ["a": 0])).isEmpty)
        XCTAssertTrue(FilterHealth.problems(in: HealthReport(loggedIn: true, path: "/direct/inbox/", counts: ["a": 0])).isEmpty)
    }

    func testHealthFromJSON() {
        let json = #"{"loggedIn":true,"path":"/","counts":{"reelsTab":0}}"#
        XCTAssertEqual(FilterHealth.problems(fromJSON: json), ["reelsTab"])
        XCTAssertTrue(FilterHealth.problems(fromJSON: "null").isEmpty)
    }

    // MARK: DeepLink

    func testDeepLinkDefaultsToInbox() throws {
        let config = try FilterResources.loadConfig()
        XCTAssertEqual(DeepLink.resolve(URL(string: "mygram://open")!, config: config)?.absoluteString,
                       "https://www.instagram.com/direct/inbox/")
    }

    func testDeepLinkAllowsPermittedPathAndRejectsBlockedOrForeign() throws {
        let config = try FilterResources.loadConfig()
        XCTAssertNotNil(DeepLink.resolve(URL(string: "mygram://open?path=/direct/inbox/")!, config: config))
        XCTAssertNil(DeepLink.resolve(URL(string: "mygram://open?path=/reels/")!, config: config))
        XCTAssertNil(DeepLink.resolve(URL(string: "mygram://open?path=//evil.com/")!, config: config))
        XCTAssertNil(DeepLink.resolve(URL(string: "mygram://open?path=https://evil.com")!, config: config))
        XCTAssertNil(DeepLink.resolve(URL(string: "other://open")!, config: config))
    }
}
