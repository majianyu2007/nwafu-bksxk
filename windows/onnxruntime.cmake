# flutter_onnxruntime 1.8.0 treats every 64-bit pointer as x64, including ARM64.
# Supply its supported system-library seam with an explicitly targeted runtime.
# Keep desktop ORT at the plugin's 1.22.0; do not change the OCR model or Dart API.
include(FetchContent)
if(FLUTTER_TARGET_PLATFORM STREQUAL "windows-arm64" OR
   CMAKE_GENERATOR_PLATFORM STREQUAL "ARM64")
  set(NWAFU_ORT_ARCH "arm64")
elseif(FLUTTER_TARGET_PLATFORM STREQUAL "windows-x64" OR
       CMAKE_GENERATOR_PLATFORM STREQUAL "x64")
  set(NWAFU_ORT_ARCH "x64")
else()
  message(FATAL_ERROR "Unsupported Windows target: ${FLUTTER_TARGET_PLATFORM}")
endif()
FetchContent_Declare(nwafu_ort
  URL "https://github.com/microsoft/onnxruntime/releases/download/v1.22.0/onnxruntime-win-${NWAFU_ORT_ARCH}-1.22.0.zip"
  TLS_VERIFY ON
)
FetchContent_MakeAvailable(nwafu_ort)
set(USE_SYSTEM_ONNXRUNTIME ON CACHE BOOL "Use the target-specific ORT" FORCE)
set(ONNXRUNTIME_ROOT_DIR "${nwafu_ort_SOURCE_DIR}" CACHE PATH "ORT root" FORCE)
set(ONNXRUNTIME_LIBRARY "${nwafu_ort_SOURCE_DIR}/lib/onnxruntime.lib" CACHE FILEPATH "ORT import library" FORCE)
set(ONNXRUNTIME_INCLUDE_DIR "${nwafu_ort_SOURCE_DIR}/include" CACHE PATH "ORT headers" FORCE)
# The plugin does not bundle libraries in system mode. Bundle every runtime DLL.
file(GLOB NWAFU_ORT_DLLS "${nwafu_ort_SOURCE_DIR}/lib/*.dll")
if(NOT NWAFU_ORT_DLLS)
  message(FATAL_ERROR "ONNX Runtime archive contains no DLLs")
endif()
