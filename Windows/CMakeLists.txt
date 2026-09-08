cmake_minimum_required(VERSION 3.16)
project(HAUTNetworkGuard VERSION 1.3.18 LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_AUTOMOC ON)
set(CMAKE_AUTORCC ON)
set(CMAKE_AUTOUIC ON)

# 查找 Qt 包
find_package(Qt6 REQUIRED COMPONENTS Core Gui Widgets Network)

# 源文件
set(SOURCES
    src/main.cpp
    src/mainwindow.cpp
    src/config.cpp
    src/api.cpp
    src/encryption.cpp
    src/protocol_utils.cpp
    src/trayicon.cpp
    src/logger.cpp
    src/instance_guard.cpp
)

# 头文件
set(HEADERS
    src/mainwindow.h
    src/config.h
    src/api.h
    src/encryption.h
    src/protocol_utils.h
    src/session_policy.h
    src/trayicon.h
    src/logger.h
    src/instance_guard.h
)

enable_testing()

add_executable(haut_session_tests tests/session_policy_tests.cpp)
set_target_properties(haut_session_tests PROPERTIES AUTOMOC OFF AUTORCC OFF AUTOUIC OFF)
add_test(NAME session_policy_tests COMMAND haut_session_tests
    "${CMAKE_CURRENT_SOURCE_DIR}/../tests/fixtures/session_scenarios.txt")

# 资源文件
set(RESOURCES
    resources/resources.qrc
)

# 创建可执行文件
add_executable(${PROJECT_NAME} WIN32
    ${SOURCES}
    ${HEADERS}
    ${RESOURCES}
)

# 链接 Qt 库
target_link_libraries(${PROJECT_NAME} PRIVATE
    Qt6::Core
    Qt6::Gui
    Qt6::Widgets
    Qt6::Network
)

add_executable(haut_smoke_tests
    tests/windows_smoke_tests.cpp
    src/config.cpp
    src/encryption.cpp
    src/logger.cpp
    src/protocol_utils.cpp
    src/config.h
    src/encryption.h
    src/logger.h
    src/protocol_utils.h
)

target_link_libraries(haut_smoke_tests PRIVATE
    Qt6::Core
)

add_test(NAME windows_smoke_tests COMMAND haut_smoke_tests)

add_executable(haut_controller_tests
    tests/controller_session_tests.cpp
    src/mainwindow.cpp src/config.cpp src/api.cpp src/encryption.cpp
    src/protocol_utils.cpp src/trayicon.cpp src/logger.cpp
    ${HEADERS}
)
target_link_libraries(haut_controller_tests PRIVATE Qt6::Core Qt6::Gui Qt6::Widgets Qt6::Network)
add_test(NAME controller_session_tests COMMAND haut_controller_tests)
set_tests_properties(controller_session_tests PROPERTIES TIMEOUT 30)

add_executable(haut_credential_tests
    tests/credential_failure_tests.cpp src/config.cpp src/logger.cpp)
target_link_libraries(haut_credential_tests PRIVATE Qt6::Core)
set_target_properties(haut_credential_tests PROPERTIES AUTOMOC OFF AUTORCC OFF AUTOUIC OFF)
add_test(NAME credential_failure_tests COMMAND haut_credential_tests)
set_tests_properties(credential_failure_tests PROPERTIES TIMEOUT 30)

add_executable(haut_instance_guard_tests
    tests/instance_guard_tests.cpp src/instance_guard.cpp)
target_link_libraries(haut_instance_guard_tests PRIVATE Qt6::Core)
add_test(NAME instance_guard_tests COMMAND haut_instance_guard_tests)
set_tests_properties(instance_guard_tests PROPERTIES TIMEOUT 10)

# Windows 特定设置
if(WIN32)
    target_link_libraries(${PROJECT_NAME} PRIVATE Crypt32)
    target_link_libraries(haut_smoke_tests PRIVATE Crypt32)
    target_link_libraries(haut_controller_tests PRIVATE Crypt32)
    target_link_libraries(haut_credential_tests PRIVATE Crypt32)
    target_link_libraries(haut_instance_guard_tests PRIVATE Crypt32)

    # 静态链接运行时
    set_property(TARGET ${PROJECT_NAME} PROPERTY
        MSVC_RUNTIME_LIBRARY "MultiThreaded$<$<CONFIG:Debug>:Debug>")
    set_property(TARGET haut_smoke_tests PROPERTY
        MSVC_RUNTIME_LIBRARY "MultiThreaded$<$<CONFIG:Debug>:Debug>")
    set_property(TARGET haut_controller_tests PROPERTY
        MSVC_RUNTIME_LIBRARY "MultiThreaded$<$<CONFIG:Debug>:Debug>")
    set_property(TARGET haut_credential_tests PROPERTY
        MSVC_RUNTIME_LIBRARY "MultiThreaded$<$<CONFIG:Debug>:Debug>")
    set_property(TARGET haut_instance_guard_tests PROPERTY
        MSVC_RUNTIME_LIBRARY "MultiThreaded$<$<CONFIG:Debug>:Debug>")
    
    # 添加版本信息
    set_target_properties(${PROJECT_NAME} PROPERTIES
        WIN32_EXECUTABLE TRUE
    )
endif()
