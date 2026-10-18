/// Short, human-readable code for a device registration: the first eight hex
/// digits of the server's device id, upper case ("D0A1B2C3").
///
/// The pending-approval screen shows it so the owner can read it to Dokan Pro
/// Support, and the admin panel shows it next to every registration, so the
/// right one is approved or replaced when several share a name (for example
/// "Android tablet" after reinstalls). It identifies a registration only; it
/// is not a credential and grants nothing.
String deviceCode(String deviceId) {
  final hex = deviceId.replaceAll('-', '');
  return (hex.length >= 8 ? hex.substring(0, 8) : hex).toUpperCase();
}
