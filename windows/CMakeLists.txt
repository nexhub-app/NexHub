# Project-level configuration.
cmake_minimum_required(VERSION 3.14)
project(nexhub LANGUAGES CXX)

# The name of the executable created for the application. Change this to change
# the on-disk name of your application.
set(BINARY_NAME "NexHub")

# Explicitly opt in to modern CMake behaviors to avoid warnings with recent
# versions of CMake.
cmake_policy(VERSION 3.14...3.25)

# CMake 4 起移除了对 cmake_minimum_required(<3.5) 的兼容：pdfx 在 configure
# 阶段用 DownloadProject 生成一个辅助工程去下载 pdfium，那个模板仍写
# `cmake_minimum_required(VERSION 2.8.12)`，于是直接硬报错
# （"Compatibility with CMake < 3.5 has been removed"）。
# 这里给本进程与它派生的子 cmake 进程补一个兼容下限，省掉每人手工设环境变量。
# 变量本体会被 cmake_minimum_required 读取；ENV 版本保证 execute_process
# 起的子 cmake 也继承到（CMake 4.0+ 两种形式都支持）。
if(NOT DEFINED CMAKE_POLICY_VERSION_MINIMUM)
  set(CMAKE_POLICY_VERSION_MINIMUM 3.5)
endif()
if(NOT DEFINED ENV{CMAKE_POLICY_VERSION_MINIMUM})
  set(ENV{CMAKE_POLICY_VERSION_MINIMUM} "3.5")
endif()

# Define build configuration option.
get_property(IS_MULTICONFIG GLOBAL PROPERTY GENERATOR_IS_MULTI_CONFIG)
if(IS_MULTICONFIG)
  set(CMAKE_CONFIGURATION_TYPES "Debug;Profile;Release"
    CACHE STRING "" FORCE)
else()
  if(NOT CMAKE_BUILD_TYPE AND NOT CMAKE_CONFIGURATION_TYPES)
    set(CMAKE_BUILD_TYPE "Debug" CACHE
      STRING "Flutter build mode" FORCE)
    set_property(CACHE CMAKE_BUILD_TYPE PROPERTY STRINGS
      "Debug" "Profile" "Release")
  endif()
endif()
# Define settings for the Profile build mode.
set(CMAKE_EXE_LINKER_FLAGS_PROFILE "${CMAKE_EXE_LINKER_FLAGS_RELEASE}")
set(CMAKE_SHARED_LINKER_FLAGS_PROFILE "${CMAKE_SHARED_LINKER_FLAGS_RELEASE}")
set(CMAKE_C_FLAGS_PROFILE "${CMAKE_C_FLAGS_RELEASE}")
set(CMAKE_CXX_FLAGS_PROFILE "${CMAKE_CXX_FLAGS_RELEASE}")

# Use Unicode for all projects.
add_definitions(-DUNICODE -D_UNICODE)

# MSVC 14.5x (VS 2026) turns <experimental/coroutine> into a hard error (STL1011);
# flutter_inappwebview_windows / permission_handler_windows still include it.
add_definitions(-D_SILENCE_EXPERIMENTAL_COROUTINE_DEPRECATION_WARNINGS)

# Compilation settings that should be applied to most targets.
#
# Be cautious about adding new options here, as plugins use this function by
# default. In most cases, you should add new options to specific targets instead
# of modifying this function.
function(APPLY_STANDARD_SETTINGS TARGET)
  target_compile_features(${TARGET} PUBLIC cxx_std_17)
  target_compile_options(${TARGET} PRIVATE /W4 /WX /wd"4100")
  target_compile_options(${TARGET} PRIVATE /EHsc)
  target_compile_definitions(${TARGET} PRIVATE "_HAS_EXCEPTIONS=0")
  target_compile_definitions(${TARGET} PRIVATE "$<$<CONFIG:Debug>:_DEBUG>")
endfunction()

# Flutter library and tool build rules.
set(FLUTTER_MANAGED_DIR "${CMAKE_CURRENT_SOURCE_DIR}/flutter")
add_subdirectory(${FLUTTER_MANAGED_DIR})

# Application build; see runner/CMakeLists.txt.
add_subdirectory("runner")

# Generated plugin build rules, which manage building the plugins and adding
# them to the application.
include(flutter/generated_plugins.cmake)


# === Installation ===
# Support files are copied into place next to the executable, so that it can
# run in place. This is done instead of making a separate bundle (as on Linux)
# so that building and running from within Visual Studio will work.
set(BUILD_BUNDLE_DIR "$<TARGET_FILE_DIR:${BINARY_NAME}>")
# Make the "install" step default, as it's required to run.
set(CMAKE_VS_INCLUDE_INSTALL_TO_DEFAULT_BUILD 1)
if(CMAKE_INSTALL_PREFIX_INITIALIZED_TO_DEFAULT)
  set(CMAKE_INSTALL_PREFIX "${BUILD_BUNDLE_DIR}" CACHE PATH "..." FORCE)
endif()

set(INSTALL_BUNDLE_DATA_DIR "${CMAKE_INSTALL_PREFIX}/data")
set(INSTALL_BUNDLE_LIB_DIR "${CMAKE_INSTALL_PREFIX}")

install(TARGETS ${BINARY_NAME} RUNTIME DESTINATION "${CMAKE_INSTALL_PREFIX}"
  COMPONENT Runtime)

# Bundle the native ECH proxy engine (built by android/rust/build-windows.sh) so
# that dart:ffi's DynamicLibrary.open("echproxy.dll") resolves it next to the exe.
# 注意：只能用 install()（与上方其余打包规则一致），不能对创建于 runner/ 子目录的
# ${BINARY_NAME} 在此层挂 add_custom_command(TARGET ...) —— CMake 要求 POST_BUILD
# 与目标同目录，否则报 "TARGET was not created in this directory"。
# 且必须位于上方 set(CMAKE_INSTALL_PREFIX "${BUILD_BUNDLE_DIR}") 之后：install()
# 的 DESTINATION 在声明处展开 ${CMAKE_INSTALL_PREFIX}，若在此前声明会把规则固化成
# 默认前缀 C:/Program Files/<name>，CI（全新缓存）上 DLL 就装进系统目录而非
# Release 产物目录；本地因 CMakeCache 缓存了旧前缀而侥幸正常。
# 来源优先级：windows/dll/echproxy.dll（build-windows.sh 的产物落点，已入库，
# CI checkout 即有）> android/rust/target/ 下的 cargo 原生产物（gitignored，仅
# 本地刚重编尚未同步到 windows/dll 时存在）。此前只查后者，CI 上因目录不存在
# 被 if(EXISTS) 静默跳过 → 发布包缺 ECH 引擎；本地因产物存在而正常，从未暴露。
set(ECHPROXY_DLL "${CMAKE_CURRENT_SOURCE_DIR}/dll/echproxy.dll")
if(NOT EXISTS "${ECHPROXY_DLL}")
  set(ECHPROXY_DLL
    "${CMAKE_CURRENT_SOURCE_DIR}/../android/rust/target/x86_64-pc-windows-msvc/release/echproxy.dll")
endif()
if(EXISTS "${ECHPROXY_DLL}")
  message(STATUS "Bundling ECH engine: ${ECHPROXY_DLL}")
  install(FILES "${ECHPROXY_DLL}" DESTINATION "${CMAKE_INSTALL_PREFIX}"
    COMPONENT Runtime OPTIONAL)
else()
  message(WARNING
    "echproxy.dll 未找到（windows/dll/ 与 android/rust/target/ 均缺失），"
    "本次构建不会打包 ECH 本地引擎，桌面端 ECH 将不可用")
endif()

install(FILES "${FLUTTER_ICU_DATA_FILE}" DESTINATION "${INSTALL_BUNDLE_DATA_DIR}"
  COMPONENT Runtime)

install(FILES "${FLUTTER_LIBRARY}" DESTINATION "${INSTALL_BUNDLE_LIB_DIR}"
  COMPONENT Runtime)

if(PLUGIN_BUNDLED_LIBRARIES)
  install(FILES "${PLUGIN_BUNDLED_LIBRARIES}"
    DESTINATION "${INSTALL_BUNDLE_LIB_DIR}"
    COMPONENT Runtime)
endif()

# Copy the native assets provided by the build.dart from all packages.
set(NATIVE_ASSETS_DIR "${PROJECT_BUILD_DIR}native_assets/windows/")
install(DIRECTORY "${NATIVE_ASSETS_DIR}"
   DESTINATION "${INSTALL_BUNDLE_LIB_DIR}"
   COMPONENT Runtime)

# Fully re-copy the assets directory on each build to avoid having stale files
# from a previous install.
set(FLUTTER_ASSET_DIR_NAME "flutter_assets")
install(CODE "
  file(REMOVE_RECURSE \"${INSTALL_BUNDLE_DATA_DIR}/${FLUTTER_ASSET_DIR_NAME}\")
  " COMPONENT Runtime)
install(DIRECTORY "${PROJECT_BUILD_DIR}/${FLUTTER_ASSET_DIR_NAME}"
  DESTINATION "${INSTALL_BUNDLE_DATA_DIR}" COMPONENT Runtime)

# Install the AOT library on non-Debug builds only.
install(FILES "${AOT_LIBRARY}" DESTINATION "${INSTALL_BUNDLE_DATA_DIR}"
  CONFIGURATIONS Profile;Release
  COMPONENT Runtime)
