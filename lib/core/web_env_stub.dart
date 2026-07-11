/// Native/stub implementation of web-env checks. On non-web platforms there is
/// no browser and no CORS restriction, so the app never needs the bridge.
library;

bool get isWebRuntime => false;
bool get isWebBridgeReady => true;
