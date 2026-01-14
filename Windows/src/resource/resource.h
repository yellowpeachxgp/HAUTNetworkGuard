#pragma once

// ============================================================================
// HAUT Network Guard - Windows
// 资源ID定义
// ============================================================================

// 图标资源
#define IDI_APP_ICON        100
#define IDI_ONLINE          101
#define IDI_OFFLINE         102
#define IDI_CHECKING        103

// 字符串资源
#define IDS_APP_NAME        200
#define IDS_VERSION         201

// 菜单ID
#define IDM_TRAY_MENU       300

// 菜单项ID
#define ID_MENU_STATUS      1001
#define ID_MENU_DETAIL      1002
#define ID_MENU_DETAIL2     1003
#define ID_MENU_LOGIN       1010
#define ID_MENU_LOGOUT      1011
#define ID_MENU_CHECK_NOW   1020
#define ID_MENU_DASHBOARD   1030
#define ID_MENU_SETTINGS    1031
#define ID_MENU_ABOUT       1032
#define ID_MENU_CHECK_UPDATE 1033
#define ID_MENU_QUIT        1040

// 自定义窗口消息
#define WM_TRAYICON         (WM_USER + 1)
#define WM_UPDATE_STATUS    (WM_USER + 2)
#define WM_LOGIN_RESULT     (WM_USER + 3)
#define WM_LOGOUT_RESULT    (WM_USER + 4)
#define WM_UPDATE_AVAILABLE (WM_USER + 5)

// 定时器ID
#define TIMER_STATUS_CHECK  1
#define TIMER_UPDATE_CHECK  2

// 时间间隔（毫秒）
#define STATUS_CHECK_INTERVAL   3000            // 3秒
#define UPDATE_CHECK_INTERVAL   86400000        // 24小时

// 窗口尺寸
#define SETTINGS_WINDOW_WIDTH   400
#define SETTINGS_WINDOW_HEIGHT  280
#define ABOUT_WINDOW_WIDTH      300
#define ABOUT_WINDOW_HEIGHT     220
#define UPDATE_WINDOW_WIDTH     420
#define UPDATE_WINDOW_HEIGHT    300
#define DASHBOARD_WINDOW_WIDTH  500
#define DASHBOARD_WINDOW_HEIGHT 400

// 应用信息
#define APP_NAME            L"HAUT Network Guard"
#define APP_VERSION         L"1.0.0"
#define APP_AUTHOR          L"YellowPeach"
#define APP_WEBSITE         L"https://github.com/yellowpeachxgp/HAUTNetworkGuard"
#define APP_QQ_GROUP        L"789860526"

// 注册表路径
#define REG_KEY_PATH        L"Software\\HAUTNetworkGuard"
#define REG_VALUE_USERNAME  L"Username"
#define REG_VALUE_PASSWORD  L"Password"
#define REG_VALUE_AUTOSAVE  L"AutoSave"
#define REG_VALUE_CONFIGURED L"HasConfigured"
#define REG_VALUE_SKIPPED_VER L"SkippedVersion"
#define REG_VALUE_LAST_CHECK L"LastUpdateCheck"

// 服务器配置
#define SERVER_IP           L"172.16.154.130"
#define LOGIN_PORT          69
#define STATUS_URL          "http://172.16.154.130/cgi-bin/rad_user_info"
#define LOGIN_URL           "http://172.16.154.130:69/cgi-bin/srun_portal"
#define AC_ID               "1"

// GitHub API
#define GITHUB_API_URL      "https://api.github.com/repos/yellowpeachxgp/HAUTNetworkGuard/releases/latest"
#define GITHUB_RELEASE_URL  L"https://github.com/yellowpeachxgp/HAUTNetworkGuard/releases"
