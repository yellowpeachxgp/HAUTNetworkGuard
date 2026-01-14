# ============================================================================
# HAUT Network Guard - Windows
# CMake 构建配置
# ============================================================================

cmake_minimum_required(VERSION 3.20)
project(HAUTNetworkGuard VERSION 1.0.0 LANGUAGES CXX)

# C++17 标准
set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

# Windows 特定设置
if(WIN32)
    # 使用 Unicode
    add_definitions(-DUNICODE -D_UNICODE)

    # 静态链接 CRT (生成单个 exe)
    set(CMAKE_MSVC_RUNTIME_LIBRARY "MultiThreaded$<$<CONFIG:Debug>:Debug>")

    # Windows 子系统 (不显示控制台)
    set(CMAKE_WIN32_EXECUTABLE ON)

    # 目标 Windows 版本
    add_definitions(-D_WIN32_WINNT=0x0A00 -DWINVER=0x0A00)
endif()

# 源文件
set(SOURCES
    src/main.cpp
    src/Application.cpp
    src/ui/DashboardWindow.cpp
)

# 头文件 (仅用于 IDE 显示)
set(HEADERS
    src/Application.h
    src/core/SrunEncryption.h
    src/core/SrunAPI.h
    src/core/NetworkStatus.h
    src/core/UpdateChecker.h
    src/config/AppConfig.h
    src/ui/TrayIcon.h
    src/ui/BaseWindow.h
    src/ui/SettingsWindow.h
    src/ui/AboutWindow.h
    src/ui/UpdateWindow.h
    src/ui/DashboardWindow.h
    src/utils/Logger.h
    src/utils/StringUtils.h
    src/utils/HttpClient.h
    src/resource/resource.h
)

# 资源文件
set(RESOURCES
    src/resource/resource.rc
)

# 创建可执行文件
add_executable(${PROJECT_NAME} WIN32
    ${SOURCES}
    ${HEADERS}
    ${RESOURCES}
)

# 链接系统库
target_link_libraries(${PROJECT_NAME} PRIVATE
    winhttp          # HTTP 请求
    comctl32         # 通用控件
    shell32          # Shell API
    advapi32         # 注册表
    gdi32            # GDI 绘图
    user32           # 窗口
    ole32            # COM
    uuid             # GUID
)

# 包含目录
target_include_directories(${PROJECT_NAME} PRIVATE
    ${CMAKE_CURRENT_SOURCE_DIR}/src
)

# Release 优化
if(CMAKE_BUILD_TYPE STREQUAL "Release" OR CMAKE_BUILD_TYPE STREQUAL "")
    if(MSVC)
        target_compile_options(${PROJECT_NAME} PRIVATE
            /O2         # 最大优化
            /GL         # 全程序优化
            /Gy         # 函数级链接
            /GS-        # 禁用缓冲区安全检查 (可选, 减小体积)
        )
        target_link_options(${PROJECT_NAME} PRIVATE
            /LTCG       # 链接时代码生成
            /OPT:REF    # 消除未引用函数
            /OPT:ICF    # 相同函数合并
        )
    endif()
endif()

# Debug 设置
if(CMAKE_BUILD_TYPE STREQUAL "Debug")
    if(MSVC)
        target_compile_definitions(${PROJECT_NAME} PRIVATE _DEBUG)
    endif()
endif()

# 设置输出名称
set_target_properties(${PROJECT_NAME} PROPERTIES
    OUTPUT_NAME "HAUTNetworkGuard"
    RUNTIME_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/bin"
)

# 复制清单文件到输出目录 (可选)
# add_custom_command(TARGET ${PROJECT_NAME} POST_BUILD
#     COMMAND ${CMAKE_COMMAND} -E copy
#         "${CMAKE_SOURCE_DIR}/src/resource/manifest.xml"
#         "$<TARGET_FILE_DIR:${PROJECT_NAME}>/HAUTNetworkGuard.exe.manifest"
# )

# 打印构建信息
message(STATUS "")
message(STATUS "==========================================")
message(STATUS "  HAUT Network Guard - Windows")
message(STATUS "  Version: ${PROJECT_VERSION}")
message(STATUS "  Build Type: ${CMAKE_BUILD_TYPE}")
message(STATUS "==========================================")
message(STATUS "")
