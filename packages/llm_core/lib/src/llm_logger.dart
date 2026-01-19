import 'package:logging/logging.dart' show Logger, Level;

/// Interface for logging in LLM packages.
///
/// This allows all LLM packages to use consistent logging while allowing
/// users to provide their own logging implementation if needed.
///
/// Example:
/// ```dart
/// // Use default implementation
/// final logger = DefaultLLMLogger('llm_ollama');
/// logger.info('Model loaded');
///
/// // Or provide custom implementation
/// class MyLogger implements LLMLogger {
///   @override
///   void fine(String message, [Object? error, StackTrace? stackTrace]) {
///     // Custom logging logic
///   }
///   // ... implement other methods
/// }
/// ```
abstract class LLMLogger {
  /// Log a fine-grained message (most verbose).
  void fine(String message, [Object? error, StackTrace? stackTrace]);

  /// Log an informational message.
  void info(String message, [Object? error, StackTrace? stackTrace]);

  /// Log a warning message.
  void warning(String message, [Object? error, StackTrace? stackTrace]);

  /// Log a severe error message.
  void severe(String message, [Object? error, StackTrace? stackTrace]);

  /// Check if a log level is enabled.
  bool isLoggable(LLMLogLevel level);

  /// Get the current log level.
  LLMLogLevel get level;
}

/// Log levels for LLM logging.
enum LLMLogLevel {
  /// Fine-grained messages (most verbose).
  fine,

  /// Informational messages.
  info,

  /// Warning messages.
  warning,

  /// Severe error messages.
  severe,
}

/// Default implementation of [LLMLogger] using the `logging` package.
///
/// This is the default logger used by LLM packages. Users can configure
/// logging via the standard `logging` package:
///
/// ```dart
/// import 'package:logging/logging.dart';
///
/// Logger.root.level = Level.INFO;
/// Logger.root.onRecord.listen((record) {
///   print('${record.level.name}: ${record.message}');
/// });
/// ```
class DefaultLLMLogger implements LLMLogger {
  /// Creates a default logger with the given name.
  DefaultLLMLogger(String name) : _logger = Logger(name);

  final Logger _logger;

  @override
  void fine(String message, [Object? error, StackTrace? stackTrace]) {
    _logger.fine(message, error, stackTrace);
  }

  @override
  void info(String message, [Object? error, StackTrace? stackTrace]) {
    _logger.info(message, error, stackTrace);
  }

  @override
  void warning(String message, [Object? error, StackTrace? stackTrace]) {
    _logger.warning(message, error, stackTrace);
  }

  @override
  void severe(String message, [Object? error, StackTrace? stackTrace]) {
    _logger.severe(message, error, stackTrace);
  }

  @override
  bool isLoggable(LLMLogLevel level) {
    final loggerLevel = _logger.level;
    return switch (level) {
      LLMLogLevel.fine => loggerLevel <= Level.FINE,
      LLMLogLevel.info => loggerLevel <= Level.INFO,
      LLMLogLevel.warning => loggerLevel <= Level.WARNING,
      LLMLogLevel.severe => loggerLevel <= Level.SEVERE,
    };
  }

  @override
  LLMLogLevel get level {
    final loggerLevel = _logger.level;
    if (loggerLevel <= Level.FINE) return LLMLogLevel.fine;
    if (loggerLevel <= Level.INFO) return LLMLogLevel.info;
    if (loggerLevel <= Level.WARNING) return LLMLogLevel.warning;
    return LLMLogLevel.severe;
  }
}
