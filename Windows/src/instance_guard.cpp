#include "instance_guard.h"
#include <QDir>
#include <QStandardPaths>

InstanceGuard::InstanceGuard()
    : m_lock(QStandardPaths::writableLocation(QStandardPaths::TempLocation) +
             "/HAUTNetworkGuard.lock") {}

InstanceGuard::~InstanceGuard() {
  if (m_acquired) m_lock.unlock();
}

bool InstanceGuard::acquire(int timeoutMs) {
  if (m_acquired) return true;
  m_acquired = m_lock.tryLock(timeoutMs);
  return m_acquired;
}
