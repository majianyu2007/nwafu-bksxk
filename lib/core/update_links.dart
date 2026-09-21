/// Only first-party HTTPS destinations are offered by the update UI.
library;

final appReleasesUri =
    Uri.https('github.com', '/majianyu2007/nwafu-bksxk/releases/latest');
final webAppUri = Uri.https('mjy.js.org', '/nwafu-bksxk/app/');
final bridgeInstallerUri =
    Uri.https('mjy.js.org', '/nwafu-bksxk/bksxk-web-bridge.user.js');

bool isOfficialUpdateLink(Uri uri) {
  if (uri.scheme != 'https' ||
      uri.userInfo.isNotEmpty ||
      uri.port != 443 ||
      uri.hasQuery ||
      uri.hasFragment) {
    return false;
  }
  if (uri == webAppUri || uri == bridgeInstallerUri || uri == appReleasesUri) {
    return true;
  }
  final segments = uri.pathSegments;
  return uri.host == 'github.com' &&
      segments.length == 5 &&
      segments[0] == 'majianyu2007' &&
      segments[1] == 'nwafu-bksxk' &&
      segments[2] == 'releases' &&
      segments[3] == 'tag' &&
      RegExp(r'^v?[0-9]+\.[0-9]+\.[0-9]+(?:\+[0-9A-Za-z.-]+)?$')
          .hasMatch(segments[4]);
}
