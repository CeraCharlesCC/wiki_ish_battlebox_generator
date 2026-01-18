import 'package:url_launcher/url_launcher.dart' as launcher;

import '../../application/ports/external_link_opener.dart';

/// Implementation of ExternalLinkOpener using url_launcher package.
class UrlLauncherExternalLinkOpener implements ExternalLinkOpener {
  const UrlLauncherExternalLinkOpener();

  @override
  Future<bool> open(Uri uri) async {
    if (await launcher.canLaunchUrl(uri)) {
      return launcher.launchUrl(uri, mode: launcher.LaunchMode.externalApplication);
    }
    return false;
  }
}
