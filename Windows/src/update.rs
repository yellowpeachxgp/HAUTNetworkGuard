//! 更新检测模块

use serde::Deserialize;

const GITHUB_API: &str = "https://api.github.com/repos/yellowpeachxgp/HAUTNetworkGuard/releases/latest";
pub const CURRENT_VERSION: &str = "1.2.3";

#[derive(Debug, Clone, Deserialize)]
pub struct ReleaseInfo {
    pub tag_name: String,
    pub name: String,
    pub body: String,
    pub html_url: String,
}

impl Default for ReleaseInfo {
    fn default() -> Self {
        Self {
            tag_name: String::new(),
            name: String::new(),
            body: String::new(),
            html_url: String::new(),
        }
    }
}

pub struct UpdateChecker {
    client: reqwest::blocking::Client,
}

impl UpdateChecker {
    pub fn new() -> Self {
        let client = reqwest::blocking::Client::builder()
            .timeout(std::time::Duration::from_secs(15))
            .user_agent("HAUTNetworkGuard")
            .build()
            .unwrap_or_default();
        Self { client }
    }

    pub fn check(&self) -> Option<ReleaseInfo> {
        match self.client.get(GITHUB_API).send() {
            Ok(resp) => {
                if let Ok(info) = resp.json::<ReleaseInfo>() {
                    Some(info)
                } else {
                    None
                }
            }
            Err(_) => None,
        }
    }

    pub fn has_update(&self) -> (bool, ReleaseInfo) {
        if let Some(info) = self.check() {
            let latest = info.tag_name.trim_start_matches('v');
            let current = CURRENT_VERSION;
            (Self::compare_versions(latest, current), info)
        } else {
            (false, ReleaseInfo::default())
        }
    }

    fn compare_versions(latest: &str, current: &str) -> bool {
        let parse = |v: &str| -> Vec<u32> {
            v.split('.').filter_map(|s| s.parse().ok()).collect()
        };
        let l = parse(latest);
        let c = parse(current);
        l > c
    }
}
