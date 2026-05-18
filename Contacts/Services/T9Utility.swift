import Foundation
import SwiftUI

// MARK: - Shared T9 Utility Functions

func charToPinyin(_ char: Character) -> String? {
    let str = String(char)
    if char.isASCII && char.isLetter {
        return str.lowercased()
    }
    let mutable = NSMutableString(string: str)
    guard CFStringTransform(mutable, nil, kCFStringTransformToLatin, false) else { return nil }
    guard CFStringTransform(mutable, nil, kCFStringTransformStripCombiningMarks, false) else { return nil }
    let result = (mutable as String).lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
    return result.isEmpty ? nil : result
}

func textToT9(_ text: String) -> String {
    var result = ""
    for char in text.lowercased() {
        if let digit = T9Utility.t9Map[char] {
            result.append(digit)
        }
    }
    return result
}

func matchedT9Length(_ matched: String, chars: [Character], startIdx: Int) -> Int {
    var len = 0
    for i in startIdx..<(startIdx + matched.count) {
        if i < chars.count {
            len += charToPinyin(chars[i]).map { textToT9($0).count } ?? 0
        }
    }
    return len
}

// MARK: - T9 Highlight Helper

func highlightT9Text(_ text: String, query: String) -> Text {
    let digits = query.filter { $0.isNumber }
    guard !digits.isEmpty else { return Text(text) }

    var result = Text("")
    var charIndex = 0
    let chars = Array(text)

    while charIndex < chars.count {
        let char = chars[charIndex]
        let charPinyin = charToPinyin(char)
        let charT9 = charPinyin.map { textToT9($0) } ?? ""

        if !charT9.isEmpty && digits.hasPrefix(charT9.prefix(1)) {
            var matched = ""
            var j = charIndex
            var remaining = digits

            while j < chars.count {
                let p = charToPinyin(chars[j])
                let t = p.map { textToT9($0) } ?? ""
                if t.isEmpty { break }

                if remaining.hasPrefix(t) {
                    matched += String(chars[j])
                    remaining = String(remaining.dropFirst(t.count))
                    j += 1
                } else if remaining.count <= t.count && t.hasPrefix(remaining) {
                    matched += String(chars[j])
                    remaining = ""
                    j += 1
                    break
                } else {
                    break
                }
            }

            if !matched.isEmpty && (remaining.isEmpty || digits.count <= matchedT9Length(matched, chars: chars, startIdx: charIndex)) {
                result = result + Text(matched).foregroundStyle(Color.accentColor)
                charIndex = j
            } else {
                result = result + Text(String(char))
                charIndex += 1
            }
        } else {
            result = result + Text(String(char))
            charIndex += 1
        }
    }

    return result
}

func highlightNumberText(_ number: String, query: String, font: Font = .caption) -> Text {
    let digits = number.filter { $0.isNumber }
    guard !query.isEmpty, let digitRange = digits.range(of: query) else {
        return Text(number).font(font).foregroundStyle(.primary)
    }
    
    let startPos = digits.distance(from: digits.startIndex, to: digitRange.lowerBound)
    let endPos = digits.distance(from: digits.startIndex, to: digitRange.upperBound)
    
    var digitCount = 0
    var before = ""
    var matched = ""
    var after = ""
    var phase = 0
    
    for char in number {
        if char.isNumber { digitCount += 1 }
        
        if phase == 0 {
            if digitCount <= startPos {
                before.append(char)
            } else {
                phase = 1
                matched.append(char)
            }
        } else if phase == 1 {
            if digitCount <= endPos {
                matched.append(char)
            } else {
                phase = 2
                after.append(char)
            }
        } else {
            after.append(char)
        }
    }
    
    return Text(before).font(font).foregroundStyle(.primary)
         + Text(matched).font(font).foregroundColor(.accentColor).bold()
         + Text(after).font(font).foregroundStyle(.primary)
}

// MARK: - T9 Map

enum T9Utility {
    static let t9Map: [Character: Character] = [
        "a": "2", "b": "2", "c": "2",
        "d": "3", "e": "3", "f": "3",
        "g": "4", "h": "4", "i": "4",
        "j": "5", "k": "5", "l": "5",
        "m": "6", "n": "6", "o": "6",
        "p": "7", "q": "7", "r": "7", "s": "7",
        "t": "8", "u": "8", "v": "8",
        "w": "9", "x": "9", "y": "9", "z": "9",
    ]
}
