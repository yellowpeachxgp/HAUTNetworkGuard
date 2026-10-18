#include "../src/mainwindow.h"
#include "../src/logger.h"
#include <QApplication>
#include <QCheckBox>
#include <QFont>
#include <QLabel>
#include <QScrollArea>
#include <QScrollBar>
#include <QSettings>
#include <QTemporaryDir>
#include <cstdio>
#include <stdexcept>

class ReplayApi : public Api {
public:
  void checkStatus(quint64) override {}
  void login(quint64, const QString &, const QString &) override {}
  void logout(quint64) override {}
};

int main(int argc, char **argv) {
  qputenv("QT_QPA_PLATFORM", "offscreen");
  QApplication app(argc, argv);
  Logger::setEnabled(false);
  int checked = 0;
  auto expect = [&](bool condition, const char *message) {
    if (!condition) throw std::runtime_error(message);
    ++checked;
  };

  // 模拟 Windows 微软雅黑等行高更大的中文字体，验证标签不会被布局压扁。
  if (!qEnvironmentVariableIsSet("HAUT_LAYOUT_NORMAL_FONT")) {
    QFont largeFont = app.font();
    largeFont.setPointSizeF(qMax(15.0, largeFont.pointSizeF() + 4.0));
    app.setFont(largeFont);
  }

  QTemporaryDir directory;
  expect(directory.isValid(), "无法创建隔离配置目录");
  QSettings settings(directory.filePath("layout.ini"), QSettings::IniFormat);
  Config config(settings);
  config.setUsername("layout-student");
  config.setPassword("layout-only");
  config.setAutoSave(true);
  config.setAutoLogin(true);
  expect(config.save(), "布局测试配置应保存成功");

  ReplayApi api;
  MainWindow window(config, &api, [] { return 0.0; }, false);
  window.show();
  QApplication::processEvents();

  expect(window.width() == 460, "主窗口宽度应保持 460");
  expect(window.height() >= 640, "主窗口高度不得低于 640");

  auto *scrollArea = window.findChild<QScrollArea *>("contentScrollArea");
  expect(scrollArea != nullptr, "主窗口必须使用可滚动内容区");
  expect(scrollArea->widget() != nullptr, "滚动内容区必须包含内容控件");

  auto verifyLabels = [&](const char *stage) {
    for (QLabel *label : window.findChildren<QLabel *>()) {
      if (!label || label->text().isEmpty()) continue;
      const int fontHeight = label->fontMetrics().height();
      if (label->height() < fontHeight) {
        throw std::runtime_error(
            QString("%1: 标签被压扁 text=%2 height=%3 font=%4")
                .arg(stage, label->text())
                .arg(label->height())
                .arg(fontHeight)
                .toStdString());
      }
      if (label->wordWrap() && label->width() > 0) {
        const int wrapped = label->heightForWidth(label->width());
        if (wrapped > 0 && label->height() < wrapped) {
          throw std::runtime_error(
              QString("%1: 自动换行标签高度不足 text=%2 height=%3 wrapped=%4")
                  .arg(stage, label->text())
                  .arg(label->height())
                  .arg(wrapped)
                  .toStdString());
        }
      }
    }
  };
  verifyLabels("初始布局");

  // 切换选项会替换提示文案，重新布局后仍不能出现文字裁切。
  for (QCheckBox *box : window.findChildren<QCheckBox *>()) {
    box->setChecked(!box->isChecked());
  }
  QApplication::processEvents();
  verifyLabels("选项切换后");

  if (qEnvironmentVariableIsSet("HAUT_LAYOUT_SCREENSHOT")) {
    window.grab().save(qEnvironmentVariable("HAUT_LAYOUT_SCREENSHOT"));
  }

  const int contentHeight = scrollArea->widget()->sizeHint().height();
  const int viewportHeight = scrollArea->viewport()->height();
  expect(contentHeight <= viewportHeight + 2 ||
             scrollArea->verticalScrollBar()->isVisible(),
         "内容超出窗口时必须提供滚动条");

  window.close();
  QApplication::processEvents();
  std::printf("Windows 布局回归通过：%d 个断言，窗口 %dx%d，内容高 %d，视口高 %d\n",
              checked, window.width(), window.height(), contentHeight,
              viewportHeight);
  return 0;
}
