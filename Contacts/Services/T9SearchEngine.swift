import Foundation
import Contacts
import os

private let logger = Logger(subsystem: "com.t9u.app", category: "T9SearchEngine")

// MARK: - Contact Index
private struct ContactIndex {
    let identifier: String
    let name: String
    let pinyinT9Tokens: [String]
    let initialT9: String
    let orgPinyinT9Tokens: [String]
    let orgInitialT9: String
    let extraPinyinT9Tokens: [String]
    let extraInitialT9: String
    let phoneNumbers: [String]
}

// MARK: - Search Result
struct T9SearchResult {
    let identifier: String
    let matchedPhoneNumbers: [String]
    let weight: Int
    let name: String
}

// MARK: - T9 Search Engine (Huawei/MTK Style)
class T9SearchEngine {
    
    private var contactIndexes: [ContactIndex] = []
    private var allContactsLoaded = false
    
    func reloadContacts(completion: (() -> Void)? = nil) {
        // 在主线程安全获取联系人数据
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            let contactDataArray = ContactStore.shared.fetchContactsForSearchData()
            
            // 到后台线程处理
            DispatchQueue.global(qos: .utility).async { [weak self] in
                guard let self = self else { return }
                
                autoreleasepool {
                    let total = contactDataArray.count
                    var indexes: [ContactIndex] = []
                    indexes.reserveCapacity(total)
                    
                    for (i, contactData) in contactDataArray.enumerated() {
                        let idx = self.buildIndex(for: contactData)
                        if !idx.name.isEmpty || !idx.phoneNumbers.isEmpty {
                            indexes.append(idx)
                        }
                        // 每100条更新一次UI（增量显示）
                        if i % 100 == 0 && i > 0 {
                            let partial = indexes
                            DispatchQueue.main.async {
                                self.contactIndexes = partial
                            }
                        }
                    }
                    
                    DispatchQueue.main.async {
                        self.contactIndexes = indexes
                        self.allContactsLoaded = true
                        completion?()
                    }
                }
            }
        }
    }

    func searchAsync(_ digits: String, callFrequency: [String: Int] = [:]) async -> [T9SearchResult] {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                guard let self = self else {
                    continuation.resume(returning: [])
                    return
                }
                let result = self.searchIdentifiers(digits, callFrequency: callFrequency)
                continuation.resume(returning: result)
            }
        }
    }
    
    func searchIdentifiers(_ digits: String, callFrequency: [String: Int] = [:]) -> [T9SearchResult] {
        let clean = digits.filter { $0.isNumber }
        guard !clean.isEmpty else { return [] }
        
        var results: [T9SearchResult] = []
        
        for idx in contactIndexes {
            let (weight, matchedNumbers) = searchContactIndex(idx, digits: clean)
            if weight > 0 {
                let boostedWeight = weight + freqBoost(callFrequency, idx.identifier)
                results.append(T9SearchResult(
                    identifier: idx.identifier,
                    matchedPhoneNumbers: matchedNumbers,
                    weight: boostedWeight,
                    name: idx.name
                ))
            }
        }
        
        results.sort {
            $0.weight != $1.weight ? $0.weight > $1.weight : $0.name < $1.name
        }
        return Array(results.prefix(30))
    }
    
    // MARK: - Core Search Logic (using ContactIndex)
    
    private func searchContactIndex(_ idx: ContactIndex, digits: String) -> (weight: Int, numbers: [String]) {
        var bestWeight = 0
        var matchedNumbers: [String] = []
        
        for phone in idx.phoneNumbers {
            let phoneDigits = phone.filter { $0.isNumber }
            if phoneDigits == digits {
                return (500, [phone])   // 电话精确匹配，权重低于姓名
            } else if phoneDigits.hasPrefix(digits) {
                if 450 > bestWeight { bestWeight = 450 }
                matchedNumbers.append(phone)
            } else if phoneDigits.hasSuffix(digits) {
                if 400 > bestWeight { bestWeight = 400 }
                matchedNumbers.append(phone)
            } else if phoneDigits.contains(digits) {
                if 300 > bestWeight { bestWeight = 300 }
                matchedNumbers.append(phone)
            }
        }
        if !matchedNumbers.isEmpty {
            return (bestWeight, matchedNumbers)
        }
        
        let allPinyinT9 = (idx.pinyinT9Tokens + idx.extraPinyinT9Tokens).joined()
        if allPinyinT9 == digits {
            return (1000, idx.phoneNumbers)   // 姓名全拼精确匹配，最高优先级
        } else if allPinyinT9.hasPrefix(digits) {
            if 900 > bestWeight { bestWeight = 900 }
        } else if matchesFromTokenStart(tokens: idx.pinyinT9Tokens, query: digits) {
            if 950 > bestWeight { bestWeight = 950 }
        } else if matchesFromTokenStart(tokens: idx.extraPinyinT9Tokens, query: digits) {
            if 850 > bestWeight { bestWeight = 850 }
        }
        
        let allInitials = (idx.initialT9 + idx.orgInitialT9 + idx.extraInitialT9).filter { $0.isNumber }
        if allInitials == digits {
            if 950 > bestWeight { bestWeight = 950 }   // 首字母精确匹配，高优先级
        } else if allInitials.hasPrefix(digits) {
            if 850 > bestWeight { bestWeight = 850 }
        } else if allInitials.contains(digits) {
            if 400 > bestWeight { bestWeight = 400 }
        }
        
        return (bestWeight, bestWeight > 0 ? matchedNumbers : [])
    }
    
    func matchesFromTokenStart(tokens: [String], query: String) -> Bool {
        for startIdx in 0..<tokens.count {
            var matched = ""
            for i in startIdx..<tokens.count {
                matched += tokens[i]
                if matched == query { return true }
                if matched.count > query.count && !matched.hasPrefix(query) { break }
                if !query.hasPrefix(matched) { break }
            }
        }
        return false
    }
    
    // MARK: - Build Index (using SafeContactData)
    
    private func buildIndex(for data: SafeContactData) -> ContactIndex {
        let name = buildFullName(from: data)
        let tokens = tokenize(name)
        
        // 拼音部分
        let pinyinParts = tokens.compactMap { $0.type == .pinyin ? $0.target : nil }
        let latinParts = tokens.compactMap { $0.type == .latin ? $0.target.lowercased() : nil }
        let allParts = pinyinParts + latinParts
        
        let pinyinT9Tokens = allParts.map { textToT9($0) }
        let initials = allParts.compactMap { $0.first.map(String.init) }.joined()
        let initialT9 = textToT9(initials)
        
        // 组织名称
        let orgTokens = tokenize(data.organizationName)
        let orgPinyinParts = orgTokens.compactMap { $0.type == .pinyin ? $0.target : nil }
        let orgLatinParts = orgTokens.compactMap { $0.type == .latin ? $0.target.lowercased() : nil }
        let orgAllParts = orgPinyinParts + orgLatinParts
        let orgPinyinT9Tokens = orgAllParts.map { textToT9($0) }
        let orgInitials = orgAllParts.compactMap { $0.first.map(String.init) }.joined()
        let orgInitialT9 = textToT9(orgInitials)
        
        // 额外字段
        var extraTexts: [String] = []
        if !data.jobTitle.isEmpty { extraTexts.append(data.jobTitle) }
        if !data.departmentName.isEmpty { extraTexts.append(data.departmentName) }
        extraTexts.append(contentsOf: data.emailUsernames)
        if !data.note.isEmpty { extraTexts.append(data.note) }
        
        let extraTokens = tokenize(extraTexts.joined(separator: " "))
        let extraPinyinParts = extraTokens.compactMap { $0.type == .pinyin ? $0.target : nil }
        let extraLatinParts = extraTokens.compactMap { $0.type == .latin ? $0.target.lowercased() : nil }
        let extraAllParts = extraPinyinParts + extraLatinParts
        let extraPinyinT9Tokens = extraAllParts.map { textToT9($0) }
        let extraInitials = extraAllParts.compactMap { $0.first.map(String.init) }.joined()
        let extraInitialT9 = textToT9(extraInitials)
        
        return ContactIndex(
            identifier: data.identifier,
            name: name,
            pinyinT9Tokens: pinyinT9Tokens,
            initialT9: initialT9,
            orgPinyinT9Tokens: orgPinyinT9Tokens,
            orgInitialT9: orgInitialT9,
            extraPinyinT9Tokens: extraPinyinT9Tokens,
            extraInitialT9: extraInitialT9,
            phoneNumbers: data.phoneNumbers
        )
    }
    
    private func buildFullName(from data: SafeContactData) -> String {
        [data.familyName, data.givenName, data.middleName]
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }
    
    // MARK: - Tokenize
    
    private enum TokenType { case pinyin, latin, unknown }
    private struct Token {
        let type: TokenType
        let source: String
        let target: String
    }
    
    private func tokenize(_ input: String) -> [Token] {
        var tokens: [Token] = []
        var latinBuffer = ""
        
        for char in input {
            if char.isASCII {
                if char.isLetter || char.isNumber {
                    latinBuffer.append(char)
                } else {
                    if !latinBuffer.isEmpty {
                        tokens.append(Token(type: .latin, source: latinBuffer, target: latinBuffer))
                        latinBuffer = ""
                    }
                }
            } else if isCJK(char) {
                if !latinBuffer.isEmpty {
                    tokens.append(Token(type: .latin, source: latinBuffer, target: latinBuffer))
                    latinBuffer = ""
                }
                if let pinyin = charToPinyin(char) {
                    tokens.append(Token(type: .pinyin, source: String(char), target: pinyin))
                } else {
                    tokens.append(Token(type: .unknown, source: String(char), target: String(char)))
                }
            } else {
                if !latinBuffer.isEmpty {
                    tokens.append(Token(type: .latin, source: latinBuffer, target: latinBuffer))
                    latinBuffer = ""
                }
                tokens.append(Token(type: .unknown, source: String(char), target: String(char)))
            }
        }
        
        if !latinBuffer.isEmpty {
            tokens.append(Token(type: .latin, source: latinBuffer, target: latinBuffer))
        }
        
        return tokens
    }
    
    private func isCJK(_ char: Character) -> Bool {
        let scalars = char.unicodeScalars
        guard let first = scalars.first else { return false }
        let val = first.value
        return (val >= 0x4E00 && val <= 0x9FFF) ||
               (val >= 0x3040 && val <= 0x30FF) ||
               (val >= 0xAC00 && val <= 0xD7AF)
    }
    
    // MARK: - Helper
    
    private func freqBoost(_ freq: [String: Int], _ identifier: String) -> Int {
        let count = freq[identifier] ?? 0
        return min(count * 5, 50)
    }
}
