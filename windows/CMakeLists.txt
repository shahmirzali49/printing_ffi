# The Flutter tooling requires that developers have a version of Visual Studio
# installed that includes CMake 3.14 or later. You should not increase this
# version, as doing so will cause the plugin to fail to compile for some
# customers of the plugin.
cmake_minimum_required(VERSION 3.14)

# --- Pdfium Dependency ---
# Use FetchContent to download and extract Pdfium binaries. This is a robust
# way to manage the dependency without requiring manual setup.
include(FetchContent)

# You can override these in the example/windows/CMakeLists.txt for testing
set(PDFIUM_VERSION "7390" CACHE STRING "Version of pdfium used")
set(PDFIUM_ARCH "x64" CACHE STRING "Architecture of pdfium used")

FetchContent_Declare(
  pdfium
  URL "https://github.com/bblanchon/pdfium-binaries/releases/download/chromium%2F${PDFIUM_VERSION}/pdfium-win-${PDFIUM_ARCH}.tgz"
  URL_HASH SHA256=7ab3f91a3341b7cfdb3c3c039428e19ae26a095006870df25da4be40635e9198
)

FetchContent_GetProperties(pdfium)
if(NOT pdfium_POPULATED)
  FetchContent_Populate(pdfium)
  message(STATUS "pdfium downloaded to ${pdfium_SOURCE_DIR}")
endif()

# Set variables for the src/CMakeLists.txt to use.
set(PDFIUM_INCLUDE_DIR "${pdfium_SOURCE_DIR}/include" CACHE PATH "Pdfium include directory")
set(PDFIUM_LIBRARY "${pdfium_SOURCE_DIR}/lib/pdfium.dll.lib" CACHE FILEPATH "Pdfium library")
set(PDFIUM_RUNTIME_LIBRARY "${pdfium_SOURCE_DIR}/bin/pdfium.dll" CACHE FILEPATH "Pdfium runtime DLL")

# Project-level configuration.
set(PROJECT_NAME "printing_ffi")
project(${PROJECT_NAME} LANGUAGES CXX)

# Invoke the build for native code shared with the other target platforms.
# This can be changed to accommodate different builds.
add_subdirectory("${CMAKE_CURRENT_SOURCE_DIR}/../src" "${CMAKE_CURRENT_BINARY_DIR}/shared")

# List of absolute paths to libraries that should be bundled with the plugin.
# This list could contain prebuilt libraries, or libraries created by an
# external build triggered from this build file.
set(printing_ffi_bundled_libraries
  # Defined in ../src/CMakeLists.txt.
  # This can be changed to accommodate different builds.
  $<TARGET_FILE:printing_ffi> # The plugin's own DLL
  "${PDFIUM_RUNTIME_LIBRARY}" # The pdfium DLL to bundle with the app
  PARENT_SCOPE
)
