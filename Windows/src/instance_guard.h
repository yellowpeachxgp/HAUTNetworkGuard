#ifndef INSTANCE_GUARD_H
#define INSTANCE_GUARD_H

#include <QLockFile>

// 每个 Windows 用户共享一个锁，前台启动和 --startup 共用同一实例。
class InstanceGuard {
public:
  InstanceGuard();
  ~InstanceGuard();

  bool acquire(int timeoutMs = 100);
  bool acquired() const { return m_acquired; }

private:
  QLockFile m_lock;
  bool m_acquired = false;
};

#endif // INSTANCE_GUARD_H
