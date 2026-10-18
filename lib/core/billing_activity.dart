/// Whether a sale is being built right now (a POS cart holds items).
///
/// Interruptions that are not about the sale itself, such as the in-app
/// update prompt, wait while this is true. Each POS workspace reports its
/// own cart; it is read on demand, never listened to, so reporting from
/// `build` is safe.
abstract final class BillingActivity {
  static final _busy = <Object>{};

  static void report(Object owner, {required bool busy}) =>
      busy ? _busy.add(owner) : _busy.remove(owner);

  static bool get isBusy => _busy.isNotEmpty;
}
