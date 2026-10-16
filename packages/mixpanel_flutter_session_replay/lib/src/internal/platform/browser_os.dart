/// Normalizes browser user agents to Mixpanel's supported OS names.
///
/// Uses the same platform ordering as mixpanel-js, without its legacy Windows
/// Phone and BlackBerry categories. Unknown user agents have no OS value.
String browserOperatingSystem(String userAgent) {
  final agent = userAgent.toLowerCase();
  if (agent.contains('windows')) return 'Windows';
  if (agent.contains('iphone') ||
      agent.contains('ipad') ||
      agent.contains('ipod')) {
    return 'iOS';
  }
  // Android user agents also contain Linux; check Android first.
  if (agent.contains('android')) return 'Android';
  if (agent.contains('mac')) return 'Mac OS X';
  if (agent.contains('linux')) return 'Linux';
  if (agent.contains('cros')) return 'Chrome OS';
  return '';
}
