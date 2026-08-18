import 'package:llm_core/llm_core.dart';

/// A calculator tool that can perform basic mathematical operations.
///
/// This tool demonstrates function calling with llama.cpp models.
class CalculatorTool extends LLMTool {
  /// Creates a calculator tool.
  ///
  /// [onInvoke] is called with the arguments the model supplied and the result
  /// handed back to it. llm_llamacpp executes tools internally and does not
  /// surface their results in the chunk stream, so this callback is how the UI
  /// gets to show what the tool actually did.
  CalculatorTool({this.onInvoke});

  /// Notified after every execution, for display purposes.
  final void Function(Map<String, dynamic> args, String result)? onInvoke;

  @override
  String get name => 'calculator';

  @override
  String get description =>
      'Performs basic mathematical operations: addition, subtraction, multiplication, and division';

  @override
  List<LLMToolParam> get parameters => [
    LLMToolParam(
      name: 'operation',
      type: 'string',
      description: 'The mathematical operation to perform',
      enums: ['add', 'subtract', 'multiply', 'divide'],
      isRequired: true,
    ),
    LLMToolParam(
      name: 'a',
      type: 'number',
      description: 'The first number',
      isRequired: true,
    ),
    LLMToolParam(
      name: 'b',
      type: 'number',
      description: 'The second number',
      isRequired: true,
    ),
  ];

  @override
  Future<String> execute(Map<String, dynamic> args, {dynamic extra}) async {
    final result = _compute(args);
    onInvoke?.call(args, result);
    return result;
  }

  String _compute(Map<String, dynamic> args) {
    // A local model can get the argument names or types wrong, and that should
    // read back to it as a tool error rather than crashing the app.
    final operation = args['operation'];
    if (operation is! String) {
      return 'Error: missing or non-string "operation"';
    }
    final a = _asDouble(args['a']);
    final b = _asDouble(args['b']);
    if (a == null || b == null) {
      return 'Error: "a" and "b" must both be numbers';
    }

    double result;
    String operationSymbol;

    switch (operation) {
      case 'add':
        result = a + b;
        operationSymbol = '+';
        break;
      case 'subtract':
        result = a - b;
        operationSymbol = '-';
        break;
      case 'multiply':
        result = a * b;
        operationSymbol = '×';
        break;
      case 'divide':
        if (b == 0) {
          return 'Error: Cannot divide by zero';
        }
        result = a / b;
        operationSymbol = '÷';
        break;
      default:
        return 'Error: Unknown operation "$operation"';
    }

    return '${_formatNumber(a)} $operationSymbol ${_formatNumber(b)} '
        '= ${_formatNumber(result)}';
  }

  /// Renders a number the way a person would write it.
  ///
  /// Everything is widened to `double` for the arithmetic, but echoing that back
  /// as `347.0 x 89.0 = 30883` gives a small model a decimal-looking operand and
  /// an integer-looking answer in the same breath, which invites it to "fix" the
  /// result by inventing separators. Integral values are therefore printed
  /// without a fractional part.
  static String _formatNumber(double value) {
    // Beyond 2^53 a double can no longer represent consecutive integers, so
    // stop claiming integrality out there and let the decimal form show.
    if (value == value.roundToDouble() && value.abs() < 1e15) {
      return value.toInt().toString();
    }
    var text = value.toStringAsFixed(4);
    // Trim only the fractional tail. Applied to a whole integer string this
    // would turn 10200 into 102, so the '.' guard is load-bearing.
    if (text.contains('.')) {
      text = text.replaceFirst(RegExp(r'0+$'), '');
      text = text.replaceFirst(RegExp(r'\.$'), '');
    }
    return text;
  }

  /// Accepts numbers and numeric strings, since models quote numbers freely.
  static double? _asDouble(dynamic value) => switch (value) {
    final num n => n.toDouble(),
    final String s => double.tryParse(s),
    _ => null,
  };
}
