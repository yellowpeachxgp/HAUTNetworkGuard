#pragma once

// ============================================================================
// HAUT Network Guard - Windows
// SRUN3K 加密算法
// ============================================================================

#include <string>
#include <sstream>
#include <iomanip>

namespace haut {

class SrunEncryption {
public:
    // 用户名加密: ASCII+4, 前缀{SRUN3}\r\n
    static std::string encryptUsername(const std::string& username) {
        std::string encrypted;
        encrypted.reserve(username.size());

        for (char c : username) {
            // 每个字符的ASCII值 +4
            encrypted += static_cast<char>(static_cast<unsigned char>(c) + 4);
        }

        // 添加前缀 "{SRUN3}\r\n"
        return "{SRUN3}\r\n" + encrypted;
    }

    // 密码加密: XOR + 位拆分算法
    // 密钥: "1234567890"
    // 密钥索引反向: key.length - 1 - (i % key.length)
    // 低4位 = (xor_result & 0x0f) + 0x36
    // 高4位 = ((xor_result >> 4) & 0x0f) + 0x63
    // 偶数位置: 低+高，奇数位置: 高+低
    static std::string encryptPassword(const std::string& password) {
        std::string encrypted;
        encrypted.reserve(password.size() * 2);

        for (size_t i = 0; i < password.size(); ++i) {
            unsigned char charValue = static_cast<unsigned char>(password[i]);

            // 密钥索引: key.length - 1 - (i % key.length)
            size_t keyIndex = KEY_LENGTH - 1 - (i % KEY_LENGTH);
            unsigned char keyCharValue = static_cast<unsigned char>(KEY[keyIndex]);

            // XOR运算
            int ki = charValue ^ keyCharValue;

            // 位拆分
            char lowBits = static_cast<char>((ki & 0x0f) + 0x36);   // 低4位 + 54
            char highBits = static_cast<char>(((ki >> 4) & 0x0f) + 0x63);  // 高4位 + 99

            // 根据索引奇偶交替组合
            if (i % 2 == 0) {
                encrypted += lowBits;
                encrypted += highBits;
            } else {
                encrypted += highBits;
                encrypted += lowBits;
            }
        }

        return encrypted;
    }

    // URL编码
    static std::string urlEncode(const std::string& str) {
        std::ostringstream escaped;
        escaped.fill('0');
        escaped << std::hex;

        for (unsigned char c : str) {
            // 保留字符: A-Z a-z 0-9 - _ . ~
            if (isalnum(c) || c == '-' || c == '_' || c == '.' || c == '~') {
                escaped << c;
            } else {
                escaped << std::uppercase;
                escaped << '%' << std::setw(2) << static_cast<int>(c);
                escaped << std::nouppercase;
            }
        }

        return escaped.str();
    }

private:
    static constexpr const char* KEY = "1234567890";
    static constexpr size_t KEY_LENGTH = 10;
};

} // namespace haut
