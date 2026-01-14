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

use eframe::egui;

pub use api::{NetworkStatus, SrunApi};
pub use config::AppConfig;
pub use update::{ReleaseInfo, UpdateChecker, CURRENT_VERSION};

/// 共享应用状态
#[derive(Clone)]
struct AppState {
    status: NetworkStatus,
    config: AppConfig,
    is_checking: bool,
}

impl Default for AppState {
    fn default() -> Self {
        Self {
            status: NetworkStatus::default(),
            config: AppConfig::load(),
            is_checking: false,
        }
    }
}

/// 主应用
struct HautApp {
    state: Arc<Mutex<AppState>>,
    api: SrunApi,
    show_settings: bool,
    show_update: bool,
    update_info: Option<ReleaseInfo>,
    username_input: String,
    password_input: String,
    remember: bool,
}

impl HautApp {
    fn new(state: Arc<Mutex<AppState>>) -> Self {
        let s = state.lock().unwrap();
        let username = s.config.username.clone();
        let password = s.config.password.clone();
        let remember = s.config.auto_save;
        let show_settings = !s.config.has_configured;
        drop(s);

        Self {
            state,
            api: SrunApi::new(),
            show_settings,
            show_update: false,
            update_info: None,
            username_input: username,
            password_input: password,
            remember,
        }
    }
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

        self.show_main_panel(ctx);
    }
}

impl HautApp {
    fn show_main_panel(&mut self, ctx: &egui::Context) {
        egui::CentralPanel::default().show(ctx, |ui| {
            ui.heading("HAUT Network Guard");
            ui.label("河南工业大学校园网自动登录工具");
            ui.separator();

            let state = self.state.lock().unwrap();
            let status = &state.status;

            // 状态显示
            ui.horizontal(|ui| {
                ui.label("状态:");
                if status.is_online {
                    ui.colored_label(egui::Color32::GREEN, "● 在线");
                } else {
                    ui.colored_label(egui::Color32::RED, "● 离线");
                }
            });

            if status.is_online {
                ui.horizontal(|ui| {
                    ui.label("IP 地址:");
                    ui.label(&status.ip_address);
                });
                ui.horizontal(|ui| {
                    ui.label("已用流量:");
                    ui.label(format_bytes(status.used_bytes));
                });
                ui.horizontal(|ui| {
                    ui.label("在线时长:");
                    ui.label(format_duration(status.online_seconds));
                });
            }
            drop(state);

            ui.separator();
            ui.horizontal(|ui| {
                if ui.button("设置").clicked() {
                    self.show_settings = true;
                }
                if ui.button("检查更新").clicked() {
                    self.check_update();
                }
            });
        });
    }

    fn show_settings_window(&mut self, ctx: &egui::Context) {
        egui::Window::new("账号设置")
            .collapsible(false)
            .resizable(false)
            .show(ctx, |ui| {
                ui.horizontal(|ui| {
                    ui.label("学号:");
                    ui.text_edit_singleline(&mut self.username_input);
                });
                ui.horizontal(|ui| {
                    ui.label("密码:");
                    ui.add(egui::TextEdit::singleline(&mut self.password_input).password(true));
                });
                ui.checkbox(&mut self.remember, "记住密码");

                ui.separator();
                ui.horizontal(|ui| {
                    if ui.button("保存").clicked() {
                        self.save_settings();
                        self.show_settings = false;
                    }
                    if ui.button("取消").clicked() {
                        self.show_settings = false;
                    }
                });
            });
    }

    fn show_update_window(&mut self, ctx: &egui::Context) {
        egui::Window::new("检查更新")
            .collapsible(false)
            .resizable(false)
            .show(ctx, |ui| {
                ui.horizontal(|ui| {
                    ui.label("当前版本:");
                    ui.label(CURRENT_VERSION);
                });

                if let Some(info) = &self.update_info {
                    ui.horizontal(|ui| {
                        ui.label("最新版本:");
                        ui.label(&info.tag_name);
                    });
                    ui.separator();
                    ui.label("更新日志:");
                    egui::ScrollArea::vertical()
                        .max_height(150.0)
                        .show(ui, |ui| {
                            ui.label(&info.body);
                        });

                    ui.separator();
                    ui.horizontal(|ui| {
                        if ui.button("立即更新").clicked() {
                            let _ = open::that(&info.html_url);
                        }
                        if ui.button("稍后更新").clicked() {
                            self.show_update = false;
                        }
                    });
                } else {
                    ui.label("已是最新版本");
                    if ui.button("关闭").clicked() {
                        self.show_update = false;
                    }
                }
            });
    }

    fn save_settings(&mut self) {
        let mut state = self.state.lock().unwrap();
        state.config.username = self.username_input.clone();
        state.config.password = self.password_input.clone();
        state.config.auto_save = self.remember;
        state.config.has_configured = true;
        let _ = state.config.save();
    }

    fn check_update(&mut self) {
        let checker = UpdateChecker::new();
        let (has_update, info) = checker.has_update();
        if has_update {
            self.update_info = Some(info);
        } else {
            self.update_info = None;
        }
        self.show_update = true;
    }
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
            {
                let mut s = state_clone.lock().unwrap();
                let was_online = s.status.is_online;
                s.status = status.clone();

                // 离线时自动登录
                if !status.is_online && s.config.has_configured && was_online {
                    let _ = api.login(&s.config.username, &s.config.password);
                }
            }
            thread::sleep(Duration::from_secs(3));
        }
    });

    let options = eframe::NativeOptions {
        viewport: egui::ViewportBuilder::default()
            .with_inner_size([400.0, 300.0])
            .with_min_inner_size([300.0, 200.0]),
        ..Default::default()
    };

    eframe::run_native(
        "HAUT Network Guard",
        options,
        Box::new(|_cc| Ok(Box::new(HautApp::new(state)))),
    )
}
