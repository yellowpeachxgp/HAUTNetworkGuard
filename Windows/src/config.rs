//! 配置管理模块

#[derive(Debug, Clone, Default)]
pub struct AppConfig {
    pub username: String,
    pub password: String,
    pub auto_save: bool,
    pub has_configured: bool,
    pub skipped_version: String,
}

#[cfg(target_os = "windows")]
mod platform {
    use super::AppConfig;
    use std::io;
    use winreg::enums::*;
    use winreg::RegKey;

    const REG_PATH: &str = r"Software\HAUTNetworkGuard";

    impl AppConfig {
        pub fn load() -> Self {
            let hkcu = RegKey::predef(HKEY_CURRENT_USER);
            let key = match hkcu.open_subkey(REG_PATH) {
                Ok(k) => k,
                Err(_) => return Self::default(),
            };

            Self {
                username: key.get_value("Username").unwrap_or_default(),
                password: decode_password(
                    &key.get_value::<String, _>("Password").unwrap_or_default()
                ),
                auto_save: key.get_value::<u32, _>("AutoSave").unwrap_or(0) == 1,
                has_configured: key.get_value::<u32, _>("HasConfigured").unwrap_or(0) == 1,
                skipped_version: key.get_value("SkippedVersion").unwrap_or_default(),
            }
        }

        pub fn save(&self) -> io::Result<()> {
            let hkcu = RegKey::predef(HKEY_CURRENT_USER);
            let (key, _) = hkcu.create_subkey(REG_PATH)?;

            key.set_value("Username", &self.username)?;
            key.set_value("Password", &encode_password(&self.password))?;
            key.set_value("AutoSave", &(self.auto_save as u32))?;
            key.set_value("HasConfigured", &(self.has_configured as u32))?;
            key.set_value("SkippedVersion", &self.skipped_version)?;

            Ok(())
        }
    }

    fn encode_password(password: &str) -> String {
        password.bytes().map(|b| (b ^ 0x5A) as char).collect()
    }

    fn decode_password(encoded: &str) -> String {
        encoded.bytes().map(|b| (b ^ 0x5A) as char).collect()
    }
}

#[cfg(not(target_os = "windows"))]
impl AppConfig {
    pub fn load() -> Self {
        Self::default()
    }

    pub fn save(&self) -> std::io::Result<()> {
        Ok(())
    }
}
