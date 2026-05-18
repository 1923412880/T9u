import Foundation

struct PhoneAttribution {
    let province: String
    let city: String
    let country: String
}

final class PhoneAttributionService {
    static let shared = PhoneAttributionService()
    
    private var phoneBuf: Data?
    private var firstPhoneRecordOffset: Int = 0
    private var phoneRecordCount: Int = 0
    private let phoneFmtLength = 9 // <iiB = 4 + 4 + 1 = 9 bytes
    
    private init() {
        loadPhoneDat()
    }
    
    func lookup(_ phone: String) -> PhoneAttribution? {
        let clean = phone.filter { $0.isNumber }
        guard !clean.isEmpty else { return nil }

        // 区分 + 前缀 和 00 前缀的国际号码
        let hasPlusPrefix = phone.hasPrefix("+")
        let hasDoubleZeroPrefix = phone.hasPrefix("00")
        let hasInternationalPrefix = hasPlusPrefix || hasDoubleZeroPrefix

        // 国际号码：去除前缀后检测国家码
        if hasInternationalPrefix {
            let digits: String
            if hasPlusPrefix {
                digits = clean
            } else {
                // 00 前缀：去掉前两位
                digits = String(clean.dropFirst(2))
            }
            guard !digits.isEmpty else { return nil }

            for len in [4, 3, 2, 1] {
                let prefix = String(digits.prefix(len))
                if let country = Self.countryDb[prefix] {
                    return PhoneAttribution(province: "", city: "", country: country)
                }
            }
            return nil
        }

        // 国内号码：检测归属地
        // 短号查询（4-6位）：银行/保险/快递/航空/运营商/政务热线
        if clean.count >= 4 && clean.count <= 6 {
            if let org = Self.shortNumberDb[clean] {
                return PhoneAttribution(province: org, city: "", country: "")
            }
        }
        if clean.count >= 7 {
            // 先查 phone.dat（手机号 13x~19x 前缀）
            if let result = lookupInPhoneDat(digits: clean) {
                return PhoneAttribution(province: result.province, city: result.city, country: "")
            }
            // phone.dat 没命中 → 尝试固话区号解析
            if clean.hasPrefix("0"), let landlineResult = lookupLandline(digits: clean) {
                return landlineResult
            }
        }

        return nil
    }
    
    // MARK: - 安全读取工具方法
    
    /// 安全读取小端序 Int32，不使用任何指针操作
    /// 使用 UInt32 构造值，再转换为 Int32（避免符号扩展问题）
    private func readInt32LE(from data: Data, at offset: Int) -> Int32? {
        guard offset + 4 <= data.count else {
            return nil
        }
        // 手动读取4个字节并构造小端序 Int32
        // 使用 UInt32 避免符号扩展问题，最后用 bitPattern 转换为 Int32
        let b0 = UInt32(data[offset])
        let b1 = UInt32(data[offset + 1]) << 8
        let b2 = UInt32(data[offset + 2]) << 16
        let b3 = UInt32(data[offset + 3]) << 24
        let uresult: UInt32 = b0 | b1 | b2 | b3
        return Int32(bitPattern: uresult)
    }
    
    private func readString(from data: Data, at offset: Int) -> String {
        guard offset < data.count else { 
            return "" 
        }
        
        // 查找 \0 结尾的位置
        var endOffset = offset
        while endOffset < data.count {
            if data[endOffset] == 0 {
                break
            }
            endOffset += 1
            
            // 安全保护：避免无限循环
            if endOffset - offset > 200 {
                break
            }
        }
        
        guard endOffset > offset else { return "" }
        
        let subdata = data.subdata(in: offset..<endOffset)
        if let result = String(data: subdata, encoding: .utf8) {
            return result
        } else {
            return ""
        }
    }
    
    // MARK: - 手机号归属地查询（通过 phone.dat）
    
    private func lookupInPhoneDat(digits: String) -> (province: String, city: String)? {
        guard let buf = phoneBuf else { 
            return nil 
        }
        guard digits.count >= 7 else { return nil }
        
        // 安全转换，避免崩溃
        guard let targetPrefix = Int32(digits.prefix(7)) else {
            return nil
        }
        
        // 二分查找
        var left = 0
        var right = phoneRecordCount - 1
        
        while left <= right {
            let middle = (left + right) / 2
            let currentOffset = firstPhoneRecordOffset + middle * phoneFmtLength
            
            guard currentOffset + phoneFmtLength <= buf.count else { 
                break 
            }
            
            // 安全读取记录：使用纯 Swift 方式，无指针操作
            guard let phonePrefix = readInt32LE(from: buf, at: currentOffset),
                  let recordOffset = readInt32LE(from: buf, at: currentOffset + 4) else {
                break
            }
            
            if phonePrefix > targetPrefix {
                right = middle - 1
            } else if phonePrefix < targetPrefix {
                left = middle + 1
            } else {
                // 找到匹配，读取记录内容
                let content = readString(from: buf, at: Int(recordOffset))
                let parts = content.split(separator: "|")
                if parts.count >= 2 {
                    return (String(parts[0]), String(parts[1]))
                }
                return nil
            }
        }
        
        return nil
    }
    
    // MARK: - 固话归属地查询（通过区号）
    
    private func lookupLandline(digits: String) -> PhoneAttribution? {
        // 固话格式：0 + 区号(3-4位) + 号码
        // 先试4位区号（更精确），再试3位区号
        if digits.count >= 5 {
            let code4 = String(digits.prefix(4))
            if let result = Self.landlineAreaCodes[code4] {
                return PhoneAttribution(province: result.province, city: result.city, country: "")
            }
        }
        if digits.count >= 4 {
            let code3 = String(digits.prefix(3))
            if let result = Self.landlineAreaCodes[code3] {
                return PhoneAttribution(province: result.province, city: result.city, country: "")
            }
        }
        return nil
    }
    
    // MARK: - phone.dat 文件加载
    
    private func loadPhoneDat() {
        // 从 Bundle 加载 phone.dat 文件
        guard let url = Bundle.main.url(forResource: "phone", withExtension: "dat") else {
            return
        }
        
        do {
            phoneBuf = try Data(contentsOf: url)
            
            // 读取文件头：版本号(4字节ASCII) + 第一条记录偏移量(4字节小端Int32)
            guard phoneBuf!.count >= 8 else {
                phoneBuf = nil
                return
            }
            
            // 读取版本号（ASCII字符串）
            let versionData = phoneBuf!.subdata(in: 0..<4)
            let version = String(data: versionData, encoding: .ascii) ?? "未知"
            
            // 读取第一条记录偏移量（小端 Int32）— 安全方式，无指针操作
            guard let firstRecordOffset = readInt32LE(from: phoneBuf!, at: 4) else {
                phoneBuf = nil
                return
            }
            
            firstPhoneRecordOffset = Int(firstRecordOffset)
            
            // 计算记录数量
            let recordDataSize = phoneBuf!.count - firstPhoneRecordOffset
            phoneRecordCount = recordDataSize / phoneFmtLength
            
            // 验证文件格式
            guard firstPhoneRecordOffset >= 8 else {
                phoneBuf = nil
                return
            }
            
            guard phoneRecordCount > 0 else {
                phoneBuf = nil
                return
            }
            
            // 验证最后一条记录的位置
            let lastRecordOffset = firstPhoneRecordOffset + (phoneRecordCount - 1) * phoneFmtLength
            if lastRecordOffset + phoneFmtLength > phoneBuf!.count {
                phoneRecordCount = (phoneBuf!.count - firstPhoneRecordOffset) / phoneFmtLength
            }
            
        } catch {
            phoneBuf = nil
        }
    }
}
