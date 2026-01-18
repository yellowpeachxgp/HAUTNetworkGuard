//! SRUN3K 加密算法模块

/// 加密用户名: ASCII + 4, 前缀 {SRUN3}\r\n
pub fn encrypt_username(username: &str) -> String {
    let encrypted: String = username
        .chars()
        .map(|c| char::from_u32(c as u32 + 4).unwrap_or(c))
        .collect();
    format!("{{SRUN3}}\r\n{}", encrypted)
}

/// 加密密码: XOR + 位拆分
/// 密钥: "1234567890", 反向索引
/// 低4位 + 0x36, 高4位 + 0x63
/// 偶数索引: low+high, 奇数索引: high+low
pub fn encrypt_password(password: &str) -> String {
    let key = b"1234567890";
    let key_len = key.len();
    let mut encrypted = String::new();

    for (i, c) in password.bytes().enumerate() {
        let key_index = key_len - 1 - (i % key_len);
        let ki = c ^ key[key_index];

        let low_bits = (ki & 0x0f) + 0x36;
        let high_bits = ((ki >> 4) & 0x0f) + 0x63;

        let low_char = char::from(low_bits);
        let high_char = char::from(high_bits);

        if i % 2 == 0 {
            encrypted.push(low_char);
            encrypted.push(high_char);
        } else {
            encrypted.push(high_char);
            encrypted.push(low_char);
        }
    }

    encrypted
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_encrypt_username() {
        let result = encrypt_username("231040600203");
        assert!(result.starts_with("{SRUN3}\r\n"));
    }

    #[test]
    fn test_encrypt_password() {
        let result = encrypt_password("test123");
        assert!(!result.is_empty());
    }
}
