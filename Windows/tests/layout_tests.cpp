#include "../src/mainwindow.h"
#include "../src/logger.h"
#include <QApplication>
#include <QCheckBox>
#include <QElapsedTimer>
#include <QFont>
#include <QGroupBox>
#include <QHash>
#include <QLabel>
#include <QScrollArea>
#include <QScrollBar>
#include <QSettings>
#include <QTemporaryDir>
#include <QWidget>
#include <cstdio>
#include <stdexcept>

class ReplayApi : public Api {
public:
  void checkStatus(quint64) override {}
  void login(quint64, const QString &, const QString &) override {}
  void logout(quint64) override {}
};

namespace {

// 同一父级下的兄弟控件由布局排布，几何不得互相重叠。
// 只比较叶子控件，避免把 GroupBox 与其子控件误判为重叠。
void verifyNoOverlap(QWidget *root, const char *stage, int *checked) {
  // 顶层卡片/分组框也必须互不重叠（截图中正是 GroupBox 相互覆盖）。
  QList<QRect> topLevel;
  for (QWidget *child : root->findChildren<QWidget *>(Qt::FindDirectChildrenOnly)) {
    if (child && child->isVisible() && !child->size().isEmpty())
      topLevel.append(child->geometry());
  }
  for (int i = 0; i < topLevel.size(); ++i) {
    for (int j = i + 1; j < topLevel.size(); ++j) {
      const QRect overlap = topLevel[i].intersected(topLevel[j]);
      if (overlap.width() > 1 && overlap.height() > 1) {
        throw std::runtime_error(
            QString("%1: 顶层卡片重叠 %2x%3").arg(stage)
                .arg(overlap.width()).arg(overlap.height()).toStdString());
      }
    }
  }

  QHash<QWidget *, QList<QWidget *>> byParent;
  for (QWidget *widget : root->findChildren<QWidget *>()) {
    if (!widget || !widget->isVisible() || widget->size().isEmpty()) continue;
    if (qobject_cast<QScrollBar *>(widget) || qobject_cast<QScrollArea *>(widget))
      continue;
    if (!widget->findChildren<QWidget *>(Qt::FindDirectChildrenOnly).isEmpty())
      continue;
    byParent[widget->parentWidget()].append(widget);
  }
  for (auto it = byParent.constBegin(); it != byParent.constEnd(); ++it) {
    const QList<QWidget *> &siblings = it.value();
    for (int i = 0; i < siblings.size(); ++i) {
      for (int j = i + 1; j < siblings.size(); ++j) {
        const QRect overlap =
            siblings[i]->geometry().intersected(siblings[j]->geometry());
        // 允许 1px 的布局取整误差。
        if (overlap.width() > 1 && overlap.height() > 1) {
          throw std::runtime_error(
              QString("%1: 控件重叠 %2/%3 -> %4x%5")
                  .arg(stage, siblings[i]->objectName().isEmpty()
                                  ? QString::fromLatin1(siblings[i]->metaObject()->className())
                                  : siblings[i]->objectName(),
                       siblings[j]->objectName().isEmpty()
                           ? QString::fromLatin1(siblings[j]->metaObject()->className())
                           : siblings[j]->objectName())
                  .arg(overlap.width())
                  .arg(overlap.height())
                  .toStdString());
        }
      }
    }
  }
  ++(*checked);
}

void verifyLabels(QWidget *root, const char *stage, int *checked) {
  for (QLabel *label : root->findChildren<QLabel *>()) {
    if (!label || label->text().isEmpty() || !label->isVisible()) continue;
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
    ++(*checked);
  }
}

} // namespace

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

  expect(window.width() >= 460, "主窗口宽度不得小于设计宽度");
  expect(window.height() >= 640, "主窗口高度不得低于 640");

  auto *scrollArea = window.findChild<QScrollArea *>("contentScrollArea");
  expect(scrollArea != nullptr, "主窗口必须使用可滚动内容区");
  expect(scrollArea->widget() != nullptr, "滚动内容区必须包含内容控件");
  expect(scrollArea->verticalScrollBarPolicy() == Qt::ScrollBarAsNeeded,
         "内容溢出时应出现纵向滚动条");
  expect(scrollArea->horizontalScrollBarPolicy() == Qt::ScrollBarAsNeeded,
         "内容过宽时应出现横向滚动条而不是压缩控件");

  verifyLabels(&window, "初始布局", &checked);
  verifyNoOverlap(scrollArea->widget(), "初始布局", &checked);

  // 切换到最长的提示文案，重新布局后仍不能出现裁切或重叠。
  for (QCheckBox *box : window.findChildren<QCheckBox *>()) {
    box->setChecked(box->text() == "自动登录 (断线重连)");
  }
  QApplication::processEvents();
  verifyLabels(&window, "自动登录开启", &checked);
  verifyNoOverlap(scrollArea->widget(), "自动登录开启", &checked);

  for (QCheckBox *box : window.findChildren<QCheckBox *>()) {
    box->setChecked(false);
  }
  QApplication::processEvents();
  verifyLabels(&window, "全部关闭", &checked);
  verifyNoOverlap(scrollArea->widget(), "全部关闭", &checked);

  // 再次放大字体（模拟系统字体/缩放变化），窗口必须重新排版。
  QFont hugeFont = app.font();
  hugeFont.setPointSizeF(hugeFont.pointSizeF() + 6.0);
  app.setFont(hugeFont);
  window.show();
  QApplication::processEvents();
  verifyLabels(&window, "字体再放大", &checked);
  verifyNoOverlap(scrollArea->widget(), "字体再放大", &checked);

  // 模拟小屏幕/用户把窗口压到最小：内容必须滚动，不能互相重叠。
  window.resize(window.width(), 560);
  QApplication::processEvents();
  verifyLabels(&window, "窗口压到最小", &checked);
  verifyNoOverlap(scrollArea->widget(), "窗口压到最小", &checked);
  expect(scrollArea->verticalScrollBar()->isVisible(),
         "窗口压到最小时必须出现纵向滚动条");

  if (qEnvironmentVariableIsSet("HAUT_LAYOUT_SCREENSHOT")) {
    window.grab().save(qEnvironmentVariable("HAUT_LAYOUT_SCREENSHOT"));
  }

  const int contentHeight = scrollArea->widget()->sizeHint().height();
  const int viewportHeight = scrollArea->viewport()->height();
  expect(contentHeight <= viewportHeight + 2 ||
             scrollArea->verticalScrollBar()->isVisible(),
         "内容超出窗口时必须提供滚动条");

  // 延迟构建 UI 的路径：先建托盘，再在显示时构建窗口。
  QSettings deferredSettings(directory.filePath("deferred.ini"), QSettings::IniFormat);
  Config deferredConfig(deferredSettings);
  deferredConfig.setUsername("deferred-student");
  deferredConfig.setPassword("deferred-only");
  deferredConfig.setAutoSave(false);
  deferredConfig.setAutoLogin(true);
  expect(deferredConfig.save(), "延迟 UI 配置应保存成功");
  ReplayApi deferredApi;
  MainWindow deferredWindow(deferredConfig, &deferredApi, [] { return 0.0; }, false, true);
  expect(deferredWindow.findChild<QScrollArea *>("contentScrollArea") == nullptr,
         "延迟模式在显示前不应构建主窗口内容");
  QElapsedTimer deferredClock;
  deferredClock.start();
  deferredWindow.show();
  QApplication::processEvents();
  const qint64 deferredElapsed = deferredClock.elapsed();
  expect(deferredWindow.findChild<QScrollArea *>("contentScrollArea") != nullptr,
         "显示后必须按需构建完整界面");
  verifyLabels(&deferredWindow, "延迟构建后", &checked);
  verifyNoOverlap(deferredWindow.findChild<QScrollArea *>("contentScrollArea")->widget(),
                  "延迟构建后", &checked);
  expect(deferredElapsed < 5000, "按需构建界面不应阻塞过久");

  deferredWindow.close();
  window.close();
  QApplication::processEvents();
  std::printf("Windows 布局回归通过：%d 个断言，窗口 %dx%d，内容高 %d，"
              "视口高 %d，延迟构建 %lldms\n",
              checked, window.width(), window.height(), contentHeight,
              viewportHeight, static_cast<long long>(deferredElapsed));
  return 0;
}
