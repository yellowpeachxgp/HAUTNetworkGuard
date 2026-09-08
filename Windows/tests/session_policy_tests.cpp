#include "../src/session_policy.h"
#include <fstream>
#include <iostream>
#include <map>
#include <sstream>
#include <stdexcept>
#include <string>

int main(int argc, char **argv) {
  if (argc != 2) return 2;
  std::ifstream input(argv[1]);
  if (!input) return 2;
  SessionPolicy policy;
  std::map<std::string, SessionPolicy::Token> tokens;
  const std::map<std::string, SessionPolicy::Observation> observations = {
      {"unknown", SessionPolicy::Observation::Unknown}, {"offline", SessionPolicy::Observation::Offline},
      {"online", SessionPolicy::Observation::Online}, {"error", SessionPolicy::Observation::Error}};
  const std::map<std::string, SessionPolicy::Operation> operations = {
      {"idle", SessionPolicy::Operation::Idle}, {"status", SessionPolicy::Operation::Status},
      {"login", SessionPolicy::Operation::Login}, {"logout", SessionPolicy::Operation::Logout}};
  int lineNumber = 0, checked = 0, scenarios = 0;
  std::string line, scenario;
  try {
    while (std::getline(input, line)) {
      ++lineNumber;
      if (line.empty() || line[0] == '#') continue;
      std::istringstream row(line);
      std::string command, alias, value;
      row >> command;
      if (command == "scenario") {
        row >> scenario;
        policy = SessionPolicy{};
        tokens.clear();
        ++scenarios;
        continue;
      }
      bool actual = false, expected = false;
      row >> alias;
      if (command == "expect") {
        bool hold = false;
        double next = -1;
        row >> value >> hold >> next;
        actual = policy.observation() == observations.at(alias) &&
                 policy.operation() == operations.at(value) &&
                 policy.manualOfflineHold() == hold && policy.nextAutomaticAttempt() == next;
        expected = true;
      } else if (command == "status_start" || command == "logout_start") {
        row >> expected;
        const auto token = command == "status_start" ? policy.beginStatus() : policy.beginLogout();
        actual = token.has_value();
        if (token) tokens[alias] = *token;
      } else if (command == "status_end") {
        row >> value >> expected;
        actual = policy.completeStatus(tokens.at(alias), observations.at(value));
      } else if (command == "login_start") {
        bool manual = false, enabled = false, credentials = false;
        double now = -1, interval = -1;
        row >> manual >> enabled >> credentials >> now >> interval >> expected;
        const auto token = policy.beginLogin(manual, enabled, credentials, now, interval);
        actual = token.has_value();
        if (token) tokens[alias] = *token;
      } else if (command == "login_end") {
        bool succeeded = false;
        double now = -1;
        row >> succeeded >> now >> expected;
        actual = policy.completeLogin(tokens.at(alias), succeeded, now);
      } else if (command == "logout_end") {
        bool succeeded = false;
        row >> succeeded >> expected;
        actual = policy.completeLogout(tokens.at(alias), succeeded);
      } else {
        throw std::runtime_error("未知事件");
      }
      if (row.fail() || actual != expected) throw std::runtime_error("行为与预期不符");
      ++checked;
    }
    if (checked == 0) throw std::runtime_error("没有执行任何断言");
  } catch (const std::exception &error) {
    std::cerr << "失败：" << scenario << "，第 " << lineNumber << " 行：" << error.what() << '\n';
    return 1;
  }
  std::cout << "C++ 会话策略通过：" << scenarios << " 个场景，" << checked << " 个事件断言\n";
}
