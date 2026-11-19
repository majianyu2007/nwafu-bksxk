# flutter_onnxruntime 1.8.0 downloads ONNX Runtime 1.22.0 from GitHub releases
# by default, which breaks whenever microsoft/onnxruntime is unavailable.
# Supply its supported system-library seam from Microsoft's official NuGet
# package (Microsoft.ML.OnnxRuntime 1.22.0), which bundles both x64 and arm64
# Linux libraries and headers with SHA-256 verification.
if(FLUTTER_TARGET_PLATFORM STREQUAL "linux-arm64" OR
   CMAKE_SYSTEM_PROCESSOR MATCHES "^(aarch64|arm64)$")
  set(NWAFU_ORT_ARCH "arm64")
elseif(FLUTTER_TARGET_PLATFORM STREQUAL "linux-x64" OR
       CMAKE_SYSTEM_PROCESSOR MATCHES "^(x86_64|amd64)$")
  set(NWAFU_ORT_ARCH "x64")
else()
  message(FATAL_ERROR
    "Unsupported Linux target: ${FLUTTER_TARGET_PLATFORM} / ${CMAKE_SYSTEM_PROCESSOR}"
  )
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
set(NWAFU_ORT_NATIVE "${NWAFU_ORT_DIR}/runtimes/linux-${NWAFU_ORT_ARCH}/native")
set(NWAFU_ORT_INCLUDE "${NWAFU_ORT_DIR}/build/native/include")
set(NWAFU_ORT_STAGE "${NWAFU_ORT_DIR}/stage-${NWAFU_ORT_ARCH}")

if(NOT EXISTS "${NWAFU_ORT_INCLUDE}/onnxruntime_cxx_api.h" OR
   NOT EXISTS "${NWAFU_ORT_NATIVE}/libonnxruntime.so")
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

# libonnxruntime.so in the NuGet package has DT_SONAME = libonnxruntime.so.1.
# Stage the real ELF under its SONAME plus a libonnxruntime.so symlink so both
# link-time resolution and runtime ld.so lookup in $ORIGIN/lib succeed.
file(MAKE_DIRECTORY "${NWAFU_ORT_STAGE}/lib")
execute_process(
  COMMAND "${CMAKE_COMMAND}" -E copy_if_different
    "${NWAFU_ORT_NATIVE}/libonnxruntime.so"
    "${NWAFU_ORT_STAGE}/lib/libonnxruntime.so.1"
  RESULT_VARIABLE NWAFU_ORT_COPY_RC
)
if(NOT NWAFU_ORT_COPY_RC EQUAL 0)
  message(FATAL_ERROR "Failed to stage libonnxruntime.so.1 (exit ${NWAFU_ORT_COPY_RC})")
endif()
execute_process(
  COMMAND "${CMAKE_COMMAND}" -E create_symlink
    libonnxruntime.so.1 "${NWAFU_ORT_STAGE}/lib/libonnxruntime.so"
)
if(EXISTS "${NWAFU_ORT_NATIVE}/libonnxruntime_providers_shared.so")
  execute_process(
    COMMAND "${CMAKE_COMMAND}" -E copy_if_different
      "${NWAFU_ORT_NATIVE}/libonnxruntime_providers_shared.so"
      "${NWAFU_ORT_STAGE}/lib/libonnxruntime_providers_shared.so"
  )
endif()

set(USE_SYSTEM_ONNXRUNTIME ON CACHE BOOL "Use the target-specific ORT" FORCE)
set(ONNXRUNTIME_ROOT_DIR "${NWAFU_ORT_STAGE}" CACHE PATH "ORT root" FORCE)
set(ONNXRUNTIME_LIBRARY "${NWAFU_ORT_STAGE}/lib/libonnxruntime.so.1" CACHE FILEPATH "ORT shared library" FORCE)
set(ONNXRUNTIME_INCLUDE_DIR "${NWAFU_ORT_INCLUDE}" CACHE PATH "ORT headers" FORCE)

set(NWAFU_ORT_LIBS
  "${NWAFU_ORT_STAGE}/lib/libonnxruntime.so.1"
  "${NWAFU_ORT_STAGE}/lib/libonnxruntime.so"
)
if(EXISTS "${NWAFU_ORT_STAGE}/lib/libonnxruntime_providers_shared.so")
  list(APPEND NWAFU_ORT_LIBS "${NWAFU_ORT_STAGE}/lib/libonnxruntime_providers_shared.so")
endif()
