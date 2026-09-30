import 'package:uuid/uuid.dart';

abstract interface class IdGenerator {
  String next();
}

final class UuidV7Generator implements IdGenerator {
  const UuidV7Generator();
  @override
  String next() => const Uuid().v7();
}
