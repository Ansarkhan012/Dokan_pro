/// PKR money stored as integer minor units (paisa).
extension type const Money(int minorUnits) implements int {
  const Money.zero() : this(0);
  Money operator +(Money other) => Money(minorUnits + other.minorUnits);
  Money operator -(Money other) => Money(minorUnits - other.minorUnits);
  Money multiply(int quantity) => Money(minorUnits * quantity);
}
Money sumMoney(Iterable<Money> values) =>
    values.fold(const Money.zero(), (a, b) => a + b);
