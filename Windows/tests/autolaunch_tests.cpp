#include "../src/config.h"
#include "../src/logger.h"
#include <QCoreApplication>
#include <QSettings>
#include <QTemporaryDir>
#include <QStringList>
#include <cstdio>
#include <stdexcept>
#include <vector>

int main(int argc, char **argv) {
  QCoreApplication app(argc, argv);
  Logger::setEnabled(false);
  int checked = 0;
  auto expect = [&](bool condition, const char *message) {
    if (!condition) throw std::runtime_error(message);
    ++checked;
  };

  try {
    const QString command =
        QStringLiteral(R"("C:/Program Files/HAUT/HAUTNetworkGuard.exe" --startup)");
    const QStringList createArgs = Config::scheduledTaskCreateArgs(command);
    expect(createArgs.contains("/Create"), "计划任务参数缺少 /Create");
    expect(createArgs.contains("/TN") &&
               createArgs.contains(Config::scheduledTaskName()),
           "计划任务参数缺少任务名");
    expect(createArgs.contains("/SC") && createArgs.contains("ONLOGON"),
           "计划任务必须在登录时触发");
    expect(createArgs.contains("/RL") && createArgs.contains("LIMITED"),
           "计划任务应使用普通用户权限，避免 UAC");
    expect(createArgs.contains("/TR"), "计划任务参数缺少执行命令");
    const int trIndex = createArgs.indexOf("/TR");
    expect(trIndex >= 0 && trIndex + 1 < createArgs.size() &&
               createArgs.at(trIndex + 1).contains("--startup"),
           "计划任务命令必须带 --startup");
    expect(Config::scheduledTaskQueryArgs().contains("/Query"),
           "计划任务查询参数缺少 /Query");
    expect(Config::scheduledTaskDeleteArgs().contains("/Delete"),
           "计划任务删除参数缺少 /Delete");

    QTemporaryDir directory;
    expect(directory.isValid(), "无法创建临时配置目录");
    QSettings settings(directory.filePath("autolaunch.ini"), QSettings::IniFormat);
    Config config(settings);
    config.setAutoLaunch(true);
    config.setStartupIntegrationForTesting(true);

    std::vector<QStringList> calls;
    bool taskExists = false;
    bool createSucceeds = true;
    config.setAutoLaunchRunnerForTesting(
        [&](const QStringList &args, int *exitCode, QString *output) {
          calls.push_back(args);
          if (args.contains("/Query")) {
            if (exitCode) *exitCode = taskExists ? 0 : 1;
            if (output)
              *output = taskExists ? "TaskName: HAUTNetworkGuard"
                                   : "ERROR: The system cannot find the file specified.";
            return true;
          }
          if (args.contains("/Create")) {
            if (createSucceeds) taskExists = true;
            if (exitCode) *exitCode = createSucceeds ? 0 : 1;
            if (output) *output = createSucceeds ? "SUCCESS" : "ERROR: Access is denied.";
            return true;
          }
          if (args.contains("/Delete")) {
            taskExists = false;
            if (exitCode) *exitCode = 0;
            if (output) *output = "SUCCESS";
            return true;
          }
          if (exitCode) *exitCode = 1;
          if (output) *output = "unexpected";
          return true;
        });

    config.repairAutoLaunchIfNeeded();
    expect(calls.size() >= 3, "自启修复应查询、创建并再次确认计划任务");
    expect(calls[0].contains("/Query"), "第一步应查询计划任务是否存在");
    expect(calls[1].contains("/Create"), "缺少计划任务时应创建");
    expect(calls.back().contains("/Query"), "创建后应回读计划任务");
    expect(taskExists, "计划任务创建后应存在");

    calls.clear();
    taskExists = false;
    createSucceeds = false;
    config.repairAutoLaunchIfNeeded();
    expect(!calls.empty() && calls.front().contains("/Query"),
           "计划任务不存在时应先查询");
    expect(calls.size() >= 2 && calls[1].contains("/Create"),
           "计划任务不存在时应尝试创建");
    expect(!taskExists, "创建失败时不应误报任务存在");

    calls.clear();
    taskExists = true;
    createSucceeds = true;
    config.repairAutoLaunchIfNeeded();
    expect(calls.size() == 1 && calls.front().contains("/Query"),
           "计划任务已存在时不应重复创建");
  } catch (const std::exception &error) {
    std::fprintf(stderr, "autolaunch test failed: %s\n", error.what());
    return 1;
  }

  std::printf("Windows 自启策略回归通过：%d 个断言\n", checked);
  return 0;
}
