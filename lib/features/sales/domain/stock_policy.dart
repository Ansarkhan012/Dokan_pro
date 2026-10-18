/// Whether a new sale may take tracked stock below zero.
///
/// Pilot rule: never. Every shop row carries `allow_negative_stock`, and it
/// defaults to true, but a sale that oversells leaves stock the shop does not
/// have. Until that setting is reviewed with the owner, sales always refuse
/// to oversell; the stored setting is not changed and still governs owner
/// stock adjustments. Stock that is already negative from earlier sales is
/// kept as recorded (history is never rewritten), and such a product cannot
/// be sold again until its stock is corrected.
bool salesMayOversell({required bool shopAllowsNegativeStock}) => false;
