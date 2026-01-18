#ifndef CONFIG_H
#define CONFIG_H

#include <QString>
#include <QSettings>

class Config {
public:
    static Config& instance();
    
    // 加载/保存配置
    void load();
    void save();
    
    // 配置项
    QString username() const { return m_username; }
    void setUsername(const QString& username) { m_username = username; }
    
    QString password() const { return m_password; }
    void setPassword(const QString& password) { m_password = password; }
    
    bool autoSave() const { return m_autoSave; }
    void setAutoSave(bool autoSave) { m_autoSave = autoSave; }
    
    bool autoLaunch() const { return m_autoLaunch; }
    void setAutoLaunch(bool autoLaunch);
    
    bool hasConfigured() const { return m_hasConfigured; }
    void setHasConfigured(bool configured) { m_hasConfigured = configured; }

private:
    Config();
    ~Config() = default;
    
    // 简单的密码混淆
    QString encodePassword(const QString& password);
    QString decodePassword(const QString& encoded);
    
    // 设置开机自启动
    void updateAutoLaunchRegistry(bool enable);
    
    QString m_username;
    QString m_password;
    bool m_autoSave = false;
    bool m_autoLaunch = false;
    bool m_hasConfigured = false;
};

#endif // CONFIG_H
