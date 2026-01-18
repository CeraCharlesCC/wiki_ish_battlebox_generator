/// Port for obtaining the current time.
///
/// Using this abstraction instead of calling `DateTime.now()` directly
/// allows for deterministic testing and time-travel scenarios.
abstract class Clock {
  DateTime now();
}

/// Default implementation that returns the system time.
class SystemClock implements Clock {
  const SystemClock();

  @override
  DateTime now() => DateTime.now();
}
