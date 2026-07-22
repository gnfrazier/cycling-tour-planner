class AppConfig {
  /// Sidecar packaging/spawning is deferred (ROADMAP.md Leg 2 scope call) —
  /// the routing backend runs as a normal dev process on a fixed port, and
  /// the client just points at it, instead of discovering a port from a
  /// spawned child (Architecture §6.3's real lifecycle is future work).
  static const String apiBaseUrl = String.fromEnvironment(
    'CTP_API_BASE_URL',
    defaultValue: 'http://127.0.0.1:8000',
  );
}
