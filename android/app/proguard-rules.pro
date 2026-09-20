# Flutter release builds run R8. Native libraries look these classes up by
# name at runtime (JNI FindClass), so R8 must not strip or rename them:
#
# - onnxruntime-android: libonnxruntime4j_jni.so resolves ai.onnxruntime.*
#   (TensorInfo, OrtException, OnnxSequence, ...). The AAR ships no consumer
#   rules, and the captcha model is warmed up at startup, so a stripped class
#   crashes the app before the login screen appears.
-keep class ai.onnxruntime.** { *; }
