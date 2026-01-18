/// Port for generating unique identifiers.
///
/// Using this abstraction instead of calling `DateTime.now().microsecondsSinceEpoch`
/// directly allows for deterministic testing.
abstract class IdGenerator {
  String newId();
}

/// Default implementation using microsecond timestamps.
class TimestampIdGenerator implements IdGenerator {
  const TimestampIdGenerator();

  @override
  String newId() => DateTime.now().microsecondsSinceEpoch.toString();
}
