#!/usr/bin/env swift

import Foundation

// MARK: - 复制 matchesAtBoundary 函数用于测试

func matchesAtBoundary(_ fullT9: String, digits: String) -> Bool {
    let parts = fullT9.components(separatedBy: " ")
    
    // 尝试从每个 part 开始匹配
    for startIdx in 0..<parts.count {
        var remaining = digits
        var matched = false
        
        for i in startIdx..<parts.count {
            if remaining.isEmpty {
                matched = true
                break
            }
            
            let part = parts[i]
            if part.hasPrefix(remaining) {
                matched = true
                break
            } else if remaining.hasPrefix(part) {
                remaining.removeFirst(part.count)
                if !remaining.isEmpty && remaining.first == " " {
                    remaining.removeFirst()
                }
            } else {
                break
            }
        }
        
        if remaining.isEmpty { matched = true }
        if matched { return true }
    }
    
    return false
}

// MARK: - 测试框架简化实现

class TestResult {
    var passed = 0
    var failed = 0
    var failures: [(String, String)] = []
    
    func recordPass() {
        passed += 1
    }
    
    func recordFailure(testName: String, message: String) {
        failed += 1
        failures.append((testName, message))
        print("  ❌ FAILED: \(message)")
    }
    
    func printSummary() {
        print("\n" + String(repeating: "=", count: 60))
        print("测试摘要")
        print(String(repeating: "=", count: 60))
        print("总计: \(passed + failed)")
        print("通过: \(passed)")
        print("失败: \(failed)")
        
        if !failures.isEmpty {
            print("\n失败的测试:")
            for (index, failure) in failures.enumerated() {
                print("  \(index + 1). \(failure.0): \(failure.1)")
            }
        }
        print(String(repeating: "=", count: 60))
    }
}

let result = TestResult()

func assert(_ condition: Bool, testName: String, message: String) {
    if condition {
        result.recordPass()
        print("  ✅ PASSED: \(testName)")
    } else {
        result.recordFailure(testName: testName, message: message)
    }
}

// MARK: - 测试用例

print("\(String(repeating: "=", count: 60))")
print("T9 搜索引擎边界匹配逻辑测试")
print(String(repeating: "=", count: 60))

// MARK: 中文姓名场景测试 ("张三" -> "zhang san" -> "9264 726")

print("\n📝 中文姓名场景测试 (\"张三\" -> \"zhang san\" -> \"9264 726\")")
print(String(repeating: "-", count: 60))

let chineseFullT9 = "9264 726"

// 1. "264" 不应该匹配 "9264 726"
assert(!matchesAtBoundary(chineseFullT9, digits: "264"),
       testName: "testChineseName_264ShouldNotMatch",
       message: "264 不应该匹配 9264 726（不在字符边界）")

// 2. "9264" 应该匹配 "9264 726"
assert(matchesAtBoundary(chineseFullT9, digits: "9264"),
       testName: "testChineseName_9264ShouldMatch",
       message: "9264 应该匹配 9264 726（完整第一个字符）")

// 3. "926" 应该匹配 "9264 726"
assert(matchesAtBoundary(chineseFullT9, digits: "926"),
       testName: "testChineseName_926ShouldMatch",
       message: "926 应该匹配 9264 726（第一个字符的前缀）")

// 4. "9264 7" 应该匹配 "9264 726"
assert(matchesAtBoundary(chineseFullT9, digits: "9264 7"),
       testName: "testChineseName_9264Space7ShouldMatch",
       message: "9264 7 应该匹配 9264 726（跨字符前缀）")

// 5. "9264726" 应该匹配 "9264 726"
assert(matchesAtBoundary(chineseFullT9, digits: "9264726"),
       testName: "testChineseName_9264726ShouldMatch",
       message: "9264726 应该匹配 9264 726（完整匹配无空格）")

// 6. "726" 应该匹配 "9264 726"
assert(matchesAtBoundary(chineseFullT9, digits: "726"),
       testName: "testChineseName_726ShouldMatch",
       message: "726 应该匹配 9264 726（完整第二个字符）")

// 7. "72" 应该匹配 "9264 726"
assert(matchesAtBoundary(chineseFullT9, digits: "72"),
       testName: "testChineseName_72ShouldMatch",
       message: "72 应该匹配 9264 726（第二个字符的前缀）")

// MARK: 英文姓名场景测试 ("John" -> "564")

print("\n📝 英文姓名场景测试 (\"John\" -> \"564\")")
print(String(repeating: "-", count: 60))

let englishFullT9 = "564"

// 8. "564" 应该匹配 "564"
assert(matchesAtBoundary(englishFullT9, digits: "564"),
       testName: "testEnglishName_564ShouldMatch",
       message: "564 应该匹配 564（John 完整匹配）")

// 9. "56" 应该匹配 "564"
assert(matchesAtBoundary(englishFullT9, digits: "56"),
       testName: "testEnglishName_56ShouldMatch",
       message: "56 应该匹配 564（John 前缀匹配）")

// 10. "64" 不应该匹配 "564"
assert(!matchesAtBoundary(englishFullT9, digits: "64"),
       testName: "testEnglishName_64ShouldNotMatch",
       message: "64 不应该匹配 564（John 不在字符边界）")

// MARK: 中英文混合场景测试 ("张三John" -> "9264 726 564")

print("\n📝 中英文混合场景测试 (\"张三John\" -> \"9264 726 564\")")
print(String(repeating: "-", count: 60))

let mixedFullT9 = "9264 726 564"

// 11. "9264 726" 应该匹配
assert(matchesAtBoundary(mixedFullT9, digits: "9264 726"),
       testName: "testMixedName_9264Space726ShouldMatch",
       message: "9264 726 应该匹配（完整中文字符）")

// 12. "564" 应该匹配
assert(matchesAtBoundary(mixedFullT9, digits: "564"),
       testName: "testMixedName_564ShouldMatch",
       message: "564 应该匹配（完整英文字符）")

// 13. "9264726564" 应该匹配（无空格完整匹配）
assert(matchesAtBoundary(mixedFullT9, digits: "9264726564"),
       testName: "testMixedName_9264726564ShouldMatch",
       message: "9264726564 应该匹配（无空格完整匹配）")

// MARK: 边界情况和额外测试

print("\n📝 边界情况和额外测试")
print(String(repeating: "-", count: 60))

// 空字符串测试
assert(matchesAtBoundary("9264 726", digits: ""),
       testName: "testEdgeCases_EmptyStringShouldMatch",
       message: "空字符串应该匹配（任意字符边界）")

// 完全匹配测试
assert(matchesAtBoundary("9264 726", digits: "9264726"),
       testName: "testEdgeCases_NoSpaceFullMatch",
       message: "无空格的完整匹配应该成功")

// 单字符测试
assert(matchesAtBoundary("5", digits: "5"),
       testName: "testEdgeCases_SingleCharExactMatch",
       message: "单字符完全匹配")
assert(!matchesAtBoundary("5", digits: "6"),
       testName: "testEdgeCases_SingleCharNoMatch",
       message: "单字符不匹配")

// MARK: 从第二个字符开始的匹配测试

print("\n📝 从第二个字符开始的匹配测试")
print(String(repeating: "-", count: 60))

let multiCharT9 = "9264 726 564"

// 从第二个字符"726"开始匹配
assert(matchesAtBoundary(multiCharT9, digits: "726"),
       testName: "testPartialMatch_SecondChar",
       message: "应该从第二个字符开始匹配")

// 从第三个字符"564"开始匹配
assert(matchesAtBoundary(multiCharT9, digits: "564"),
       testName: "testPartialMatch_ThirdChar",
       message: "应该从第三个字符开始匹配")

// 跨第二、三个字符匹配
assert(matchesAtBoundary(multiCharT9, digits: "726 564"),
       testName: "testPartialMatch_SecondAndThirdChar",
       message: "应该跨第二、三个字符匹配")

// MARK: 确保不会误匹配

print("\n📝 确保不会误匹配（关键测试）")
print(String(repeating: "-", count: 60))

// 最重要的测试："264" 不应该匹配（这是修复前要解决的bug）
assert(!matchesAtBoundary("9264 726", digits: "264"),
       testName: "testNoFalsePositives_264ShouldNotMatch",
       message: "264 不应该匹配 9264（缺少前面的9）- 这是最关键的测试")

// "66" 不应该匹配
assert(!matchesAtBoundary("9264 726", digits: "66"),
       testName: "testNoFalsePositives_66ShouldNotMatch",
       message: "66 不应该匹配 9264 726")

// "26" 不应该匹配（跨越边界）
assert(!matchesAtBoundary("9264 726", digits: "26"),
       testName: "testNoFalsePositives_26ShouldNotMatch",
       message: "26 不应该匹配（跨越字符边界）")

// MARK: 测试摘要

result.printSummary()

// 退出代码
exit(result.failed > 0 ? 1 : 0)
