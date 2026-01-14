//! 网络 API 模块

use crate::encryption;
use std::collections::HashMap;
use std::time::Duration;

const STATUS_URL: &str = "http://172.16.154.130/cgi-bin/rad_user_info";
const LOGIN_URL: &str = "http://172.16.154.130:69/cgi-bin/srun_portal";

#[derive(Debug, Clone, Default)]
pub struct NetworkStatus {
    pub is_online: bool,
    pub username: String,
    pub ip_address: String,
    pub used_bytes: u64,
    pub online_seconds: u64,
    pub error_message: String,
}

#[derive(Debug)]
pub struct LoginResult {
    pub success: bool,
    pub message: String,
}

pub struct SrunApi {
    client: reqwest::blocking::Client,
}

impl SrunApi {
    pub fn new() -> Self {
        let client = reqwest::blocking::Client::builder()
            .timeout(Duration::from_secs(10))
            .build()
            .unwrap_or_default();
        Self { client }
    }

    pub fn check_status(&self) -> NetworkStatus {
        match self.client.get(STATUS_URL).send() {
            Ok(resp) => {
                if let Ok(text) = resp.text() {
                    Self::parse_status(&text)
                } else {
                    NetworkStatus::default()
                }
            }
            Err(e) => NetworkStatus {
                error_message: e.to_string(),
                ..Default::default()
            },
        }
    }

    fn parse_status(text: &str) -> NetworkStatus {
        if text.is_empty() || text.contains("not_online") {
            return NetworkStatus::default();
        }

        let parts: Vec<&str> = text.split(',').collect();
        if parts.len() >= 4 {
            NetworkStatus {
                is_online: true,
                username: parts[0].to_string(),
                online_seconds: parts[1].parse().unwrap_or(0),
                ip_address: parts[2].to_string(),
                used_bytes: parts[3].parse().unwrap_or(0),
                error_message: String::new(),
            }
        } else {
            NetworkStatus::default()
        }
    }

    pub fn login(&self, username: &str, password: &str) -> LoginResult {
        let enc_user = encryption::encrypt_username(username);
        let enc_pass = encryption::encrypt_password(password);

        let mut params = HashMap::new();
        params.insert("action", "login");
        params.insert("ac_id", "1");
        params.insert("drop", "0");
        params.insert("pop", "1");
        params.insert("type", "10");
        params.insert("n", "117");
        params.insert("mbytes", "0");
        params.insert("minutes", "0");
        params.insert("mac", "02:00:00:00:00:00");

        let body = format!(
            "action=login&username={}&password={}&ac_id=1&drop=0&pop=1&type=10&n=117&mbytes=0&minutes=0&mac=02:00:00:00:00:00",
            urlencoding::encode(&enc_user),
            urlencoding::encode(&enc_pass)
        );

        match self.client.post(LOGIN_URL)
            .header("Content-Type", "application/x-www-form-urlencoded")
            .body(body)
            .send()
        {
            Ok(resp) => {
                let text = resp.text().unwrap_or_default();
                if text.contains("login_ok") || text.contains("already_online") {
                    LoginResult { success: true, message: "登录成功".to_string() }
                } else {
                    LoginResult { success: false, message: text }
                }
            }
            Err(e) => LoginResult { success: false, message: e.to_string() },
        }
    }

    pub fn logout(&self) -> LoginResult {
        let body = "action=logout";
        match self.client.post(LOGIN_URL)
            .header("Content-Type", "application/x-www-form-urlencoded")
            .body(body)
            .send()
        {
            Ok(resp) => {
                let text = resp.text().unwrap_or_default();
                if text.contains("logout_ok") || text.contains("not_online") {
                    LoginResult { success: true, message: "注销成功".to_string() }
                } else {
                    LoginResult { success: false, message: text }
                }
            }
            Err(e) => LoginResult { success: false, message: e.to_string() },
        }
    }
}
