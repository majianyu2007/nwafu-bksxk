# flutter_onnxruntime 1.8.0 treats every 64-bit pointer as x64, including ARM64,
# and its built-in downloader targets GitHub releases (which can go offline).
# Supply its supported system-library seam from Microsoft's official NuGet
# package (Microsoft.ML.OnnxRuntime 1.22.0), which bundles both x64 and arm64
# binaries and headers with SHA-256 verification.
if(FLUTTER_TARGET_PLATFORM STREQUAL "windows-arm64" OR
   CMAKE_GENERATOR_PLATFORM STREQUAL "ARM64")
  set(NWAFU_ORT_ARCH "arm64")
elseif(FLUTTER_TARGET_PLATFORM STREQUAL "windows-x64" OR
       CMAKE_GENERATOR_PLATFORM STREQUAL "x64")
  set(NWAFU_ORT_ARCH "x64")
else()
  message(FATAL_ERROR "Unsupported Windows target: ${FLUTTER_TARGET_PLATFORM}")
endif()

set(NWAFU_ORT_VERSION "1.22.0")
set(NWAFU_ORT_URL
  "https://api.nuget.org/v3-flatcontainer/microsoft.ml.onnxruntime/${NWAFU_ORT_VERSION}/microsoft.ml.onnxruntime.${NWAFU_ORT_VERSION}.nupkg"
)
set(NWAFU_ORT_SHA256
  "d571e63a2329baacb713f441e65ad75284de354db6e1ac435fe4bebbb417986a"
)
set(NWAFU_ORT_DIR "${CMAKE_BINARY_DIR}/_deps/nwafu_ort-${NWAFU_ORT_VERSION}")
set(NWAFU_ORT_ARCHIVE "${NWAFU_ORT_DIR}/onnxruntime.zip")
set(NWAFU_ORT_NATIVE "${NWAFU_ORT_DIR}/runtimes/win-${NWAFU_ORT_ARCH}/native")
set(NWAFU_ORT_INCLUDE "${NWAFU_ORT_DIR}/build/native/include")

if(NOT EXISTS "${NWAFU_ORT_INCLUDE}/onnxruntime_cxx_api.h" OR
   NOT EXISTS "${NWAFU_ORT_NATIVE}/onnxruntime.lib")
  file(MAKE_DIRECTORY "${NWAFU_ORT_DIR}")
  message(STATUS "Downloading Microsoft.ML.OnnxRuntime ${NWAFU_ORT_VERSION} from NuGet...")
  file(DOWNLOAD "${NWAFU_ORT_URL}" "${NWAFU_ORT_ARCHIVE}"
    EXPECTED_HASH "SHA256=${NWAFU_ORT_SHA256}"
    TLS_VERIFY ON
    STATUS NWAFU_ORT_DL_STATUS
  )
  list(GET NWAFU_ORT_DL_STATUS 0 NWAFU_ORT_DL_CODE)
  list(GET NWAFU_ORT_DL_STATUS 1 NWAFU_ORT_DL_MSG)
  if(NOT NWAFU_ORT_DL_CODE EQUAL 0)
    file(REMOVE "${NWAFU_ORT_ARCHIVE}")
    message(FATAL_ERROR
      "Failed to download ONNX Runtime from NuGet (${NWAFU_ORT_DL_CODE}): ${NWAFU_ORT_DL_MSG}"
    )
  endif()
  execute_process(
    COMMAND "${CMAKE_COMMAND}" -E tar xf "${NWAFU_ORT_ARCHIVE}"
    WORKING_DIRECTORY "${NWAFU_ORT_DIR}"
    RESULT_VARIABLE NWAFU_ORT_EXTRACT_RC
  )
  file(REMOVE "${NWAFU_ORT_ARCHIVE}")
  if(NOT NWAFU_ORT_EXTRACT_RC EQUAL 0)
    message(FATAL_ERROR
      "Failed to extract ONNX Runtime NuGet package (exit ${NWAFU_ORT_EXTRACT_RC})"
    )
  endif()
endif()

set(USE_SYSTEM_ONNXRUNTIME ON CACHE BOOL "Use the target-specific ORT" FORCE)
set(ONNXRUNTIME_ROOT_DIR "${NWAFU_ORT_DIR}" CACHE PATH "ORT root" FORCE)
set(ONNXRUNTIME_LIBRARY "${NWAFU_ORT_NATIVE}/onnxruntime.lib" CACHE FILEPATH "ORT import library" FORCE)
set(ONNXRUNTIME_INCLUDE_DIR "${NWAFU_ORT_INCLUDE}" CACHE PATH "ORT headers" FORCE)
# The plugin does not bundle libraries in system mode. Bundle every runtime DLL.
file(GLOB NWAFU_ORT_DLLS "${NWAFU_ORT_NATIVE}/*.dll")
if(NOT NWAFU_ORT_DLLS)
  message(FATAL_ERROR "ONNX Runtime archive contains no DLLs in ${NWAFU_ORT_NATIVE}")
endif()
