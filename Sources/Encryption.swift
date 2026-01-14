import Foundation

/// SRUN3K 加密模块
/// 移植自 ehaut 项目的 JavaScript 加密算法
struct SrunEncryption {

    /// 加密用户名
    /// 算法：每个字符 ASCII +4，前缀 "{SRUN3}\r\n"
    static func encryptUsername(_ username: String) -> String {
        var encrypted = ""
        for char in username {
            if let scalar = char.unicodeScalars.first {
                let newValue = scalar.value + 4
                if let newScalar = UnicodeScalar(newValue) {
                    encrypted += String(newScalar)
                }
            }
        }
        return "{SRUN3}\r\n" + encrypted
    }

    /// 加密密码
    /// 算法：XOR 加密，密钥 "1234567890"，按位拆分后交替组合
    static func encryptPassword(_ password: String) -> String {
        let key = "1234567890"
        let keyChars = Array(key)
        var encrypted = ""

        for (i, char) in password.enumerated() {
            guard let charValue = char.asciiValue else { continue }

            // 计算密钥索引：key.length - 1 - (i % key.length)
            let keyIndex = key.count - 1 - (i % key.count)
            guard let keyCharValue = keyChars[keyIndex].asciiValue else { continue }

            // XOR 运算
            let ki = Int(charValue) ^ Int(keyCharValue)

            // 拆分为低4位和高4位
            let lowBits = (ki & 0x0f) + 0x36
            let highBits = ((ki >> 4) & 0x0f) + 0x63

            let lowChar = Character(UnicodeScalar(lowBits)!)
            let highChar = Character(UnicodeScalar(highBits)!)

            // 根据索引奇偶交替组合
            if i % 2 == 0 {
                encrypted += String(lowChar) + String(highChar)
            } else {
                encrypted += String(highChar) + String(lowChar)
            }
        }

        return encrypted
    }
}
