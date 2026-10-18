#ifndef SESSION_POLICY_H
#define SESSION_POLICY_H

#include <algorithm>
#include <cstdint>
#include <optional>

// 由 UI 线程驱动；时间使用单调时钟的秒数，不受系统校时影响。
class SessionPolicy {
public:
  enum class Observation { Unknown, Offline, Online, Error };
  enum class Operation { Idle, Status, Login, Logout };
  using Token = std::uint64_t;

  Observation observation() const { return m_observation; }
  Operation operation() const { return m_operation; }
  bool isBusy() const { return m_operation != Operation::Idle; }
  bool manualOfflineHold() const { return m_manualOfflineHold; }
  double nextAutomaticAttempt() const { return m_nextAutomaticAttempt; }

  std::optional<Token> beginStatus() { return begin(Operation::Status); }

  bool completeStatus(Token token, Observation observation) {
    if (!finish(token, Operation::Status)) return false;
    m_observation = observation;
    if (observation == Observation::Online) {
      m_failures = 0;
      m_nextAutomaticAttempt = 0;
    }
    // 检测结果不能撤销用户的手动离线意图。
    return true;
  }

  std::optional<Token> beginLogin(bool manual, bool enabled, bool hasCredentials,
                                  double now, double interval) {
    if (isBusy() || !hasCredentials) return std::nullopt;
    if (!manual && (!enabled || m_manualOfflineHold ||
                    m_observation != Observation::Offline || now < m_nextAutomaticAttempt))
      return std::nullopt;
    const auto token = begin(Operation::Login);
    if (!token) return std::nullopt;
    if (manual) m_manualOfflineHold = false;
    m_observation = Observation::Unknown;
    m_attemptInterval = std::max(60.0, interval);
    m_nextAutomaticAttempt = now + m_attemptInterval;
    return token;
  }

  bool completeLogin(Token token, bool succeeded, double now) {
    if (!finish(token, Operation::Login)) return false;
    // 认证成功仍需状态接口确认在线，不能复用登录前的离线结果。
    m_observation = succeeded ? Observation::Unknown : Observation::Error;
    m_failures = succeeded ? 0 : std::min(m_failures + 1, 4);
    const double multiplier = 1 << std::max(0, m_failures - 1);
    const double delay = std::min(m_attemptInterval * multiplier,
                                  std::max(300.0, m_attemptInterval));
    m_nextAutomaticAttempt = now + delay;
    return true;
  }

  std::optional<Token> beginLogout() {
    const auto token = begin(Operation::Logout);
    if (!token) return std::nullopt;
    m_manualOfflineHold = true;
    m_observation = Observation::Unknown;
    return token;
  }

  bool completeLogout(Token token, bool succeeded) {
    if (!finish(token, Operation::Logout)) return false;
    m_observation = succeeded ? Observation::Offline : Observation::Unknown;
    return true;
  }

private:
  std::optional<Token> begin(Operation operation) {
    if (isBusy()) return std::nullopt;
    m_operation = operation;
    return ++m_sequence;
  }

  bool finish(Token token, Operation operation) {
    if (token != m_sequence || m_operation != operation) return false;
    m_operation = Operation::Idle;
    return true;
  }

  Observation m_observation = Observation::Unknown;
  Operation m_operation = Operation::Idle;
  bool m_manualOfflineHold = false;
  Token m_sequence = 0;
  int m_failures = 0;
  double m_attemptInterval = 60;
  double m_nextAutomaticAttempt = 0;
};

#endif
