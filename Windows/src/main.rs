//! HAUT Network Guard - Windows 版本
//! 河南工业大学校园网自动登录工具

#![windows_subsystem = "windows"]

mod api;
mod config;
mod encryption;
mod update;

use std::sync::{Arc, Mutex};
use std::thread;
use std::time::Duration;

use eframe::egui::{self, FontData, FontDefinitions, FontFamily};

pub use api::{NetworkStatus, SrunApi};
pub use config::AppConfig;
pub use update::{ReleaseInfo, UpdateChecker, CURRENT_VERSION};

/// 更新检测结果
#[derive(Clone)]
enum UpdateCheckResult {
    Checking,
    HasUpdate(ReleaseInfo),
    NoUpdate(ReleaseInfo),
    Error(String),
}

/// 共享应用状态
#[derive(Clone)]
struct AppState {
    status: NetworkStatus,
    config: AppConfig,
}

impl Default for AppState {
    fn default() -> Self {
        Self {
            status: NetworkStatus::default(),
            config: AppConfig::load(),
        }
    }
}

/// 主应用
struct HautApp {
    state: Arc<Mutex<AppState>>,
    show_settings: bool,
    show_update: bool,
    show_about: bool,
    update_result: UpdateCheckResult,
    username_input: String,
    password_input: String,
    remember: bool,
    auto_launch: bool,
}

impl HautApp {
    fn new(cc: &eframe::CreationContext<'_>, state: Arc<Mutex<AppState>>) -> Self {
        // 配置中文字体
        setup_fonts(&cc.egui_ctx);

        let s = state.lock().unwrap();
        let username = s.config.username.clone();
        let password = s.config.password.clone();
        let remember = s.config.auto_save;
        let auto_launch = s.config.auto_launch;
        let show_settings = !s.config.has_configured;
        drop(s);

        Self {
            state,
            show_settings,
            show_update: false,
            show_about: false,
            update_result: UpdateCheckResult::Checking,
            username_input: username,
            password_input: password,
            remember,
            auto_launch,
        }
    }
}

/// 配置中文字体
fn setup_fonts(ctx: &egui::Context) {
    let mut fonts = FontDefinitions::default();

    // 尝试加载 Windows 系统中文字体
    #[cfg(target_os = "windows")]
    {
        // Microsoft YaHei 字体路径
        let font_paths = [
            "C:\\Windows\\Fonts\\msyh.ttc",
            "C:\\Windows\\Fonts\\msyh.ttf",
            "C:\\Windows\\Fonts\\simhei.ttf",
            "C:\\Windows\\Fonts\\simsun.ttc",
        ];

        for path in &font_paths {
            if let Ok(font_data) = std::fs::read(path) {
                fonts.font_data.insert(
                    "chinese".to_owned(),
                    FontData::from_owned(font_data).into(),
                );
                // 将中文字体添加到字体族
                fonts
                    .families
                    .entry(FontFamily::Proportional)
                    .or_default()
                    .insert(0, "chinese".to_owned());
                fonts
                    .families
                    .entry(FontFamily::Monospace)
                    .or_default()
                    .insert(0, "chinese".to_owned());
                break;
            }
        }
    }

    ctx.set_fonts(fonts);
}

impl eframe::App for HautApp {
    fn update(&mut self, ctx: &egui::Context, _frame: &mut eframe::Frame) {
        ctx.request_repaint_after(Duration::from_secs(1));

        if self.show_settings {
            self.show_settings_window(ctx);
        }

        if self.show_update {
            self.show_update_window(ctx);
        }

        if self.show_about {
            self.show_about_window(ctx);
        }

        self.show_main_panel(ctx);
    }
}

impl HautApp {
    fn show_main_panel(&mut self, ctx: &egui::Context) {
        egui::CentralPanel::default().show(ctx, |ui| {
            ui.vertical_centered(|ui| {
                ui.add_space(10.0);
                ui.heading("HAUT Network Guard");
                ui.label("河南工业大学校园网自动登录工具");
            });

            ui.add_space(10.0);
            ui.separator();
            ui.add_space(10.0);

            let state = self.state.lock().unwrap();
            let status = &state.status;

            // 状态卡片
            egui::Frame::none()
                .fill(if status.is_online {
                    egui::Color32::from_rgb(230, 255, 230)
                } else {
                    egui::Color32::from_rgb(255, 230, 230)
                })
                .rounding(8.0)
                .inner_margin(12.0)
                .show(ui, |ui| {
                    ui.horizontal(|ui| {
                        ui.label("状态:");
                        if status.is_online {
                            ui.colored_label(egui::Color32::DARK_GREEN, "● 在线");
                        } else {
                            ui.colored_label(egui::Color32::DARK_RED, "● 离线");
                        }
                    });

                    if status.is_online {
                        ui.add_space(8.0);
                        egui::Grid::new("status_grid")
                            .num_columns(2)
                            .spacing([20.0, 6.0])
                            .show(ui, |ui| {
                                ui.label("IP 地址:");
                                ui.label(&status.ip_address);
                                ui.end_row();

                                ui.label("已用流量:");
                                ui.label(format_bytes(status.used_bytes));
                                ui.end_row();

                                ui.label("在线时长:");
                                ui.label(format_duration(status.online_seconds));
                                ui.end_row();

                                ui.label("用户名:");
                                ui.label(&status.username);
                                ui.end_row();
                            });
                    }
                });

            drop(state);

            ui.add_space(15.0);
            ui.separator();
            ui.add_space(10.0);

            // 操作按钮
            ui.horizontal(|ui| {
                if ui.button("  设置  ").clicked() {
                    self.show_settings = true;
                }
                if ui.button("检查更新").clicked() {
                    self.check_update();
                }
                if ui.button("关于").clicked() {
                    self.show_about = true;
                }
            });

            // 底部版本信息
            ui.with_layout(egui::Layout::bottom_up(egui::Align::Center), |ui| {
                ui.add_space(5.0);
                ui.label(
                    egui::RichText::new(format!("v{} by YellowPeach", CURRENT_VERSION))
                        .small()
                        .color(egui::Color32::GRAY),
                );
            });
        });
    }

    fn show_settings_window(&mut self, ctx: &egui::Context) {
        egui::Window::new("账号设置")
            .collapsible(false)
            .resizable(false)
            .anchor(egui::Align2::CENTER_CENTER, [0.0, 0.0])
            .show(ctx, |ui| {
                ui.add_space(10.0);

                egui::Grid::new("settings_grid")
                    .num_columns(2)
                    .spacing([10.0, 10.0])
                    .show(ui, |ui| {
                        ui.label("学号:");
                        ui.add(egui::TextEdit::singleline(&mut self.username_input).desired_width(200.0));
                        ui.end_row();

                        ui.label("密码:");
                        ui.add(
                            egui::TextEdit::singleline(&mut self.password_input)
                                .password(true)
                                .desired_width(200.0),
                        );
                        ui.end_row();
                    });

                ui.add_space(10.0);
                ui.separator();
                ui.add_space(5.0);

                // 选项区域
                ui.horizontal(|ui| {
                    ui.checkbox(&mut self.remember, "记住密码");
                    ui.add_space(20.0);
                    ui.checkbox(&mut self.auto_launch, "开机自启动");
                });

                ui.add_space(5.0);
                ui.label(
                    egui::RichText::new("开启后，每次开机将自动启动并保持网络连接")
                        .small()
                        .color(egui::Color32::GRAY),
                );

                ui.add_space(10.0);
                ui.separator();
                ui.add_space(10.0);

                ui.horizontal(|ui| {
                    if ui.button("  保存  ").clicked() {
                        self.save_settings();
                        self.show_settings = false;
                    }
                    ui.add_space(10.0);
                    if ui.button("  取消  ").clicked() {
                        self.show_settings = false;
                    }
                });
            });
    }

    fn show_update_window(&mut self, ctx: &egui::Context) {
        egui::Window::new("检查更新")
            .collapsible(false)
            .resizable(false)
            .anchor(egui::Align2::CENTER_CENTER, [0.0, 0.0])
            .default_width(400.0)
            .show(ctx, |ui| {
                match &self.update_result {
                    UpdateCheckResult::Checking => {
                        ui.vertical_centered(|ui| {
                            ui.add_space(20.0);
                            ui.spinner();
                            ui.add_space(10.0);
                            ui.label("正在检查更新...");
                            ui.add_space(20.0);
                        });
                    }

                    UpdateCheckResult::HasUpdate(info) => {
                        // 有新版本
                        ui.vertical_centered(|ui| {
                            ui.colored_label(egui::Color32::from_rgb(0, 120, 215), "⬇ 发现新版本");
                        });

                        ui.add_space(10.0);
                        ui.separator();
                        ui.add_space(10.0);

                        egui::Grid::new("version_grid")
                            .num_columns(2)
                            .spacing([20.0, 6.0])
                            .show(ui, |ui| {
                                ui.label("当前版本:");
                                ui.label(format!("v{}", CURRENT_VERSION));
                                ui.end_row();

                                ui.label("最新版本:");
                                ui.colored_label(egui::Color32::DARK_GREEN, &info.tag_name);
                                ui.end_row();
                            });

                        ui.add_space(10.0);
                        ui.label("更新日志:");
                        egui::ScrollArea::vertical()
                            .max_height(150.0)
                            .show(ui, |ui| {
                                ui.label(simplify_release_notes(&info.body));
                            });

                        ui.add_space(10.0);
                        ui.separator();
                        ui.add_space(10.0);

                        ui.horizontal(|ui| {
                            if ui.button("立即更新").clicked() {
                                let _ = open::that(&info.html_url);
                                self.show_update = false;
                            }
                            ui.add_space(10.0);
                            if ui.button("稍后提醒").clicked() {
                                self.show_update = false;
                            }
                        });
                    }

                    UpdateCheckResult::NoUpdate(info) => {
                        // 已是最新版本
                        ui.vertical_centered(|ui| {
                            ui.colored_label(egui::Color32::DARK_GREEN, "✓ 已是最新版本");
                        });

                        ui.add_space(10.0);
                        ui.separator();
                        ui.add_space(10.0);

                        egui::Grid::new("version_grid")
                            .num_columns(2)
                            .spacing([20.0, 6.0])
                            .show(ui, |ui| {
                                ui.label("当前版本:");
                                ui.label(format!("v{}", CURRENT_VERSION));
                                ui.end_row();

                                ui.label("最新版本:");
                                ui.label(&info.tag_name);
                                ui.end_row();
                            });

                        ui.add_space(10.0);
                        ui.label("当前版本更新日志:");
                        egui::ScrollArea::vertical()
                            .max_height(120.0)
                            .show(ui, |ui| {
                                ui.label(simplify_release_notes(&info.body));
                            });

                        ui.add_space(10.0);
                        ui.separator();
                        ui.add_space(10.0);

                        ui.horizontal(|ui| {
                            if ui.button("  关闭  ").clicked() {
                                self.show_update = false;
                            }
                        });
                    }

                    UpdateCheckResult::Error(msg) => {
                        // 检测失败
                        ui.vertical_centered(|ui| {
                            ui.colored_label(egui::Color32::DARK_RED, "⚠ 检测更新失败");
                        });

                        ui.add_space(10.0);
                        ui.separator();
                        ui.add_space(10.0);

                        ui.label(format!("当前版本: v{}", CURRENT_VERSION));
                        ui.add_space(10.0);

                        egui::Frame::none()
                            .fill(egui::Color32::from_rgb(255, 240, 240))
                            .rounding(4.0)
                            .inner_margin(10.0)
                            .show(ui, |ui| {
                                ui.label("无法连接到 GitHub 服务器获取版本信息。");
                                ui.add_space(5.0);
                                ui.label("可能的原因:");
                                ui.label("• 网络连接问题");
                                ui.label("• GitHub 服务暂时不可用");
                                ui.add_space(5.0);
                                ui.label(format!("错误详情: {}", msg));
                            });

                        ui.add_space(10.0);
                        ui.separator();
                        ui.add_space(10.0);

                        ui.horizontal(|ui| {
                            if ui.button("  重试  ").clicked() {
                                self.check_update();
                            }
                            ui.add_space(10.0);
                            if ui.button("  关闭  ").clicked() {
                                self.show_update = false;
                            }
                        });
                    }
                }
            });
    }

    fn show_about_window(&mut self, ctx: &egui::Context) {
        egui::Window::new("关于")
            .collapsible(false)
            .resizable(false)
            .anchor(egui::Align2::CENTER_CENTER, [0.0, 0.0])
            .default_width(320.0)
            .show(ctx, |ui| {
                ui.vertical_centered(|ui| {
                    ui.add_space(10.0);
                    ui.heading("HAUT Network Guard");
                    ui.add_space(5.0);
                    ui.label(
                        egui::RichText::new("河南工业大学校园网自动登录工具")
                            .color(egui::Color32::GRAY),
                    );
                });

                ui.add_space(15.0);
                ui.separator();
                ui.add_space(10.0);

                egui::Grid::new("about_grid")
                    .num_columns(2)
                    .spacing([20.0, 8.0])
                    .show(ui, |ui| {
                        ui.label("版本:");
                        ui.label(format!("v{}", CURRENT_VERSION));
                        ui.end_row();

                        ui.label("作者:");
                        ui.label("YellowPeach");
                        ui.end_row();

                        ui.label("QQ群:");
                        if ui.link("789860526").clicked() {
                            let _ = open::that(
                                "https://qm.qq.com/q/wlNBnpMVfE"
                            );
                        }
                        ui.end_row();

                        ui.label("项目主页:");
                        if ui.link("GitHub").clicked() {
                            let _ = open::that(
                                "https://github.com/yellowpeachxgp/HAUTNetworkGuard"
                            );
                        }
                        ui.end_row();
                    });

                ui.add_space(15.0);
                ui.separator();
                ui.add_space(10.0);

                ui.vertical_centered(|ui| {
                    if ui.button("  关闭  ").clicked() {
                        self.show_about = false;
                    }
                });

                ui.add_space(5.0);
            });
    }

    fn save_settings(&mut self) {
        let mut state = self.state.lock().unwrap();
        state.config.username = self.username_input.clone();
        state.config.password = self.password_input.clone();
        state.config.auto_save = self.remember;
        state.config.auto_launch = self.auto_launch;
        state.config.has_configured = true;
        let _ = state.config.save();
    }

    fn check_update(&mut self) {
        self.update_result = UpdateCheckResult::Checking;
        self.show_update = true;

        let checker = UpdateChecker::new();
        match checker.check() {
            Some(info) => {
                let latest = info.tag_name.trim_start_matches('v');
                let current = CURRENT_VERSION;
                if compare_versions(latest, current) {
                    self.update_result = UpdateCheckResult::HasUpdate(info);
                } else {
                    self.update_result = UpdateCheckResult::NoUpdate(info);
                }
            }
            None => {
                self.update_result = UpdateCheckResult::Error("无法获取版本信息".to_string());
            }
        }
    }
}

/// 简化更新说明
fn simplify_release_notes(notes: &str) -> String {
    let mut result = notes.to_string();
    result = result.replace("### ", "▸ ");
    result = result.replace("## ", "■ ");
    result = result.replace("# ", "● ");
    result = result.replace("- ", "  • ");
    result.trim().to_string()
}

/// 比较版本号
fn compare_versions(latest: &str, current: &str) -> bool {
    let parse = |v: &str| -> Vec<u32> {
        v.split('.').filter_map(|s| s.parse().ok()).collect()
    };
    let l = parse(latest);
    let c = parse(current);
    l > c
}

fn format_bytes(bytes: u64) -> String {
    const GB: u64 = 1024 * 1024 * 1024;
    const MB: u64 = 1024 * 1024;
    const KB: u64 = 1024;

    if bytes >= GB {
        format!("{:.2} GB", bytes as f64 / GB as f64)
    } else if bytes >= MB {
        format!("{:.2} MB", bytes as f64 / MB as f64)
    } else if bytes >= KB {
        format!("{:.2} KB", bytes as f64 / KB as f64)
    } else {
        format!("{} B", bytes)
    }
}

fn format_duration(seconds: u64) -> String {
    let hours = seconds / 3600;
    let minutes = (seconds % 3600) / 60;
    let secs = seconds % 60;
    format!("{}小时{}分{}秒", hours, minutes, secs)
}

fn main() -> eframe::Result<()> {
    let state = Arc::new(Mutex::new(AppState::default()));
    let state_clone = Arc::clone(&state);

    // 后台状态检测线程
    thread::spawn(move || {
        let api = SrunApi::new();
        loop {
            let status = api.check_status();
            let should_login;
            let username;
            let password;

            {
                let mut s = state_clone.lock().unwrap();
                s.status = status.clone();

                // 离线且已配置时自动登录
                should_login = !status.is_online && s.config.has_configured;
                username = s.config.username.clone();
                password = s.config.password.clone();
            }

            // 在锁外执行登录，避免阻塞 GUI
            if should_login && !username.is_empty() && !password.is_empty() {
                let login_result = api.login(&username, &password);
                if login_result.success {
                    // 登录成功后立即刷新状态
                    thread::sleep(Duration::from_millis(500));
                    let new_status = api.check_status();
                    let mut s = state_clone.lock().unwrap();
                    s.status = new_status;
                }
            }

            thread::sleep(Duration::from_secs(3));
        }
    });

    let options = eframe::NativeOptions {
        viewport: egui::ViewportBuilder::default()
            .with_inner_size([420.0, 350.0])
            .with_min_inner_size([350.0, 280.0])
            .with_title("HAUT Network Guard"),
        ..Default::default()
    };

    eframe::run_native(
        "HAUT Network Guard",
        options,
        Box::new(|cc| Ok(Box::new(HautApp::new(cc, state)))),
    )
}
