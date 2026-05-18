import XCTest
@testable import T9u

/// T9 搜索引擎核心匹配逻辑测试
/// 测试 matchesFromTokenStart 核心算法以及 tokenize / isCJK 等工具方法
class T9SearchEngineTests: XCTestCase {

    var engine: T9SearchEngine!

    override func setUp() {
        super.setUp()
        engine = T9SearchEngine()
    }

    override func tearDown() {
        engine = nil
        super.tearDown()
    }

    // MARK: - matchesFromTokenStart 测试（核心匹配算法）

    /// "张三" → tokens = ["9264", "726"]（zhang, san）
    /// 输入 "926" 应该匹配 "9264" 的前缀
    func testMatchesFromTokenStart_PrefixMatch() {
        let tokens = ["9264", "726"]
        let result = engine.matchesFromTokenStart(tokens: tokens, query: "926")
        XCTAssertTrue(result, "926 应该匹配 zhang(9264) 的前缀")
    }

    /// 输入 "9264" 应该精确匹配 "zhang"
    func testMatchesFromTokenStart_ExactMatch() {
        let tokens = ["9264", "726"]
        let result = engine.matchesFromTokenStart(tokens: tokens, query: "9264")
        XCTAssertTrue(result, "9264 应该精确匹配 zhang")
    }

    /// 输入 "9264726" 应该完整匹配 "zhangsan"
    func testMatchesFromTokenStart_FullMatch() {
        let tokens = ["9264", "726"]
        let result = engine.matchesFromTokenStart(tokens: tokens, query: "9264726")
        XCTAssertTrue(result, "9264726 应该完整匹配 zhangsan")
    }

    /// 输入 "726" 应该从第二个 token 匹配 "san"
    func testMatchesFromTokenStart_SecondToken() {
        let tokens = ["9264", "726"]
        let result = engine.matchesFromTokenStart(tokens: tokens, query: "726")
        XCTAssertTrue(result, "726 应该从第二个 token 匹配 san")
    }

    /// "264" 不在 token 边界开始，不应该匹配
    func testMatchesFromTokenStart_NonBoundaryShouldNotMatch() {
        let tokens = ["9264", "726"]
        let result = engine.matchesFromTokenStart(tokens: tokens, query: "264")
        XCTAssertFalse(result, "264 不应该匹配（不在 token 边界）")
    }

    /// "72" 是 "726" 的前缀，应该匹配
    func testMatchesFromTokenStart_PrefixOfSecondToken() {
        let tokens = ["9264", "726"]
        let result = engine.matchesFromTokenStart(tokens: tokens, query: "72")
        XCTAssertTrue(result, "72 应该匹配 san(726) 的前缀")
    }

    /// 跨 token 匹配："926472" → zhang(9264) + sa(72)
    func testMatchesFromTokenStart_CrossToken() {
        let tokens = ["9264", "726"]
        let result = engine.matchesFromTokenStart(tokens: tokens, query: "926472")
        XCTAssertTrue(result, "926472 应该跨 token 匹配")
    }

    /// 空字符串应该匹配
    func testMatchesFromTokenStart_EmptyQuery() {
        let tokens = ["9264", "726"]
        let result = engine.matchesFromTokenStart(tokens: tokens, query: "")
        XCTAssertTrue(result, "空 query 应该匹配")
    }

    /// 完全不匹配
    func testMatchesFromTokenStart_NoMatch() {
        let tokens = ["9264", "726"]
        let result = engine.matchesFromTokenStart(tokens: tokens, query: "11111")
        XCTAssertFalse(result, "11111 不应该匹配任何模式")
    }

    // MARK: - 三个字的名字测试

    /// "王小明" → tokens = ["9264", "9426", "6464"]（wang, xiao, ming）
    func testMatchesFromTokenStart_ThreeCharName() {
        let tokens = ["9264", "9426", "6464"]
        // 92649 → wang(9264) + x(9)
        let result1 = engine.matchesFromTokenStart(tokens: tokens, query: "92649")
        XCTAssertTrue(result1, "92649 应该混合匹配 wang + xiao 的首字母")

        // 92649426 → wang(9264) + xiao(9426)
        let result2 = engine.matchesFromTokenStart(tokens: tokens, query: "92649426")
        XCTAssertTrue(result2, "92649426 应该匹配 wangxiao")
    }

    // MARK: - 英文名测试

    /// "Bell Kate" → tokens = ["2355", "5283"]
    func testMatchesFromTokenStart_EnglishName() {
        let tokens = ["2355", "5283"]
        let result1 = engine.matchesFromTokenStart(tokens: tokens, query: "2355")
        XCTAssertTrue(result1, "2355 应该精确匹配 Bell")

        let result2 = engine.matchesFromTokenStart(tokens: tokens, query: "23")
        XCTAssertTrue(result2, "23 应该匹配 Be 前缀")

        let result3 = engine.matchesFromTokenStart(tokens: tokens, query: "355")
        XCTAssertFalse(result3, "355 不应该匹配（不在 token 边界）")
    }

    // MARK: - 性能测试

    func testPerformance_MatchesFromTokenStart() {
        let tokens = ["9264", "726", "9426", "6464", "2355", "5283"]
        measure {
            for _ in 0..<10000 {
                _ = engine.matchesFromTokenStart(tokens: tokens, query: "9264726")
                _ = engine.matchesFromTokenStart(tokens: tokens, query: "9426646")
            }
        }
    }
}
