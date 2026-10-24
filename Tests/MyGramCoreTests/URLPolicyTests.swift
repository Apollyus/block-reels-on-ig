import XCTest
@testable import MyGramCore

final class URLPolicyTests: XCTestCase {
    private func makePolicy() throws -> URLPolicy {
        URLPolicy(config: try FilterResources.loadConfig())
    }

    private func url(_ path: String) -> URL { URL(string: "https://www.instagram.com" + path)! }

    func testReelsFeedRedirectsHome() throws {
        var p = try makePolicy()
        XCTAssertEqual(p.decide(from: url("/"), to: url("/reels/"), userInitiated: true), .redirectHome)
        XCTAssertEqual(p.decide(from: nil, to: url("/reels"), userInitiated: false), .redirectHome)
        XCTAssertEqual(p.decide(from: url("/"), to: url("/reels/audio/123/"), userInitiated: true), .redirectHome)
    }

    func testExploreRedirectsHome() throws {
        var p = try makePolicy()
        XCTAssertEqual(p.decide(from: url("/"), to: url("/explore/"), userInitiated: true), .redirectHome)
        XCTAssertEqual(p.decide(from: url("/"), to: url("/explore/tags/cats/"), userInitiated: true), .redirectHome)
        XCTAssertEqual(p.decide(from: url("/"), to: url("/explore/people/"), userInitiated: true), .redirectHome)
    }

    func testSearchIsAllowed() throws {
        var p = try makePolicy()
        XCTAssertEqual(p.decide(from: url("/"), to: url("/explore/search/"), userInitiated: true), .allow)
    }

    func testReelFromDirectIsAllowedAndRemembered() throws {
        var p = try makePolicy()
        XCTAssertEqual(p.decide(from: url("/direct/t/1/"), to: url("/reel/AAA/"), userInitiated: true), .allow)
        XCTAssertEqual(p.allowedReelId, "AAA")
    }

    func testReelsPathFromDirectIsAllowedButNotFromFeed() throws {
        var p = try makePolicy()
        XCTAssertEqual(p.decide(from: url("/direct/inbox/"), to: url("/reels/AAA/"), userInitiated: true), .allow)
        var q = try makePolicy()
        XCTAssertEqual(q.decide(from: url("/"), to: url("/reels/AAA/"), userInitiated: true), .redirectHome)
    }

    func testPostFromDirectIsAllowed() throws {
        var p = try makePolicy()
        XCTAssertEqual(p.decide(from: url("/direct/t/1/"), to: url("/p/BBB/"), userInitiated: true), .allow)
        XCTAssertEqual(p.allowedReelId, "BBB")
    }

    func testReelFromProfileFeedAndSearchIsAllowed() throws {
        var p = try makePolicy()
        XCTAssertEqual(p.decide(from: url("/someone/"), to: url("/someone/reel/CCC/"), userInitiated: true), .allow)
        XCTAssertEqual(p.decide(from: url("/"), to: url("/reel/DDD/"), userInitiated: true), .allow)
        XCTAssertEqual(p.decide(from: url("/explore/search/"), to: url("/p/EEE/"), userInitiated: true), .allow)
    }

    func testSwipeToAnotherReelIsBlocked() throws {
        var p = try makePolicy()
        _ = p.decide(from: url("/direct/t/1/"), to: url("/reel/AAA/"), userInitiated: true)
        XCTAssertEqual(p.decide(from: url("/reel/AAA/"), to: url("/reel/BBB/"), userInitiated: false), .blockAndGoBack)
        XCTAssertEqual(p.allowedReelId, "AAA")
    }

    func testSwipeBlockedAlsoForReelsPathAndProfileForm() throws {
        var p = try makePolicy()
        _ = p.decide(from: url("/direct/t/1/"), to: url("/reels/AAA/"), userInitiated: true)
        XCTAssertEqual(p.decide(from: url("/reels/AAA/"), to: url("/reels/BBB/"), userInitiated: false), .blockAndGoBack)
    }

    func testUserClickToAnotherReelIsAllowed() throws {
        var p = try makePolicy()
        _ = p.decide(from: url("/direct/t/1/"), to: url("/reel/AAA/"), userInitiated: true)
        XCTAssertEqual(p.decide(from: url("/reel/AAA/"), to: url("/reel/BBB/"), userInitiated: true), .allow)
        XCTAssertEqual(p.allowedReelId, "BBB")
    }

    func testBackToSameReelIsAllowed() throws {
        var p = try makePolicy()
        _ = p.decide(from: url("/direct/t/1/"), to: url("/reel/AAA/"), userInitiated: true)
        XCTAssertEqual(p.decide(from: url("/reel/AAA/"), to: url("/reel/AAA/"), userInitiated: false), .allow)
    }

    func testOrdinaryPagesAreAllowed() throws {
        var p = try makePolicy()
        for path in ["/", "/direct/inbox/", "/direct/t/1/", "/stories/someone/123/", "/someone/", "/accounts/login/"] {
            XCTAssertEqual(p.decide(from: url("/"), to: url(path), userInitiated: true), .allow, path)
        }
    }

    func testProfileReelsTabRedirectsHome() throws {
        var p = try makePolicy()
        XCTAssertEqual(p.decide(from: url("/someone/"), to: url("/someone/reels/"), userInitiated: true), .redirectHome)
    }

    func testLeavingReelClearsAllowedId() throws {
        var p = try makePolicy()
        _ = p.decide(from: url("/direct/t/1/"), to: url("/reel/AAA/"), userInitiated: true)
        _ = p.decide(from: url("/reel/AAA/"), to: url("/direct/inbox/"), userInitiated: true)
        XCTAssertNil(p.allowedReelId)
    }

    func testExternalHostsOpenInSafari() throws {
        var p = try makePolicy()
        XCTAssertEqual(p.decide(from: url("/"), to: URL(string: "https://example.com/x")!, userInitiated: true), .openInSafari)
        XCTAssertEqual(p.decide(from: url("/"), to: URL(string: "https://evilinstagram.com/")!, userInitiated: true), .openInSafari)
        XCTAssertEqual(p.decide(from: url("/"), to: URL(string: "mailto:a@b.cz")!, userInitiated: true), .openInSafari)
    }

    func testInstagramCdnHostsAreAllowed() throws {
        var p = try makePolicy()
        XCTAssertEqual(p.decide(from: url("/"), to: URL(string: "https://scontent.cdninstagram.com/v/a.jpg")!, userInitiated: false), .allow)
        XCTAssertEqual(p.decide(from: url("/"), to: URL(string: "https://scontent.xx.fbcdn.net/v/a.jpg")!, userInitiated: false), .allow)
        XCTAssertEqual(p.decide(from: url("/"), to: URL(string: "https://l.instagram.com/?u=x")!, userInitiated: true), .allow)
    }
}
