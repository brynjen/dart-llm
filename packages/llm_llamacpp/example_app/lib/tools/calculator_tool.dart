import 'package:llm_core/llm_core.dart';

/// A calculator tool that can perform basic mathematical operations.
///
/// This tool demonstrates function calling with llama.cpp models.
class CalculatorTool extends LLMTool {
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
    final operation = args['operation'] as String;
    final a = (args['a'] as num).toDouble();
    final b = (args['b'] as num).toDouble();

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

    // Format result nicely (remove unnecessary decimals)
    final resultStr = result == result.toInt()
        ? result.toInt().toString()
        : result
              .toStringAsFixed(4)
              .replaceAll(RegExp(r'0+$'), '')
              .replaceAll(RegExp(r'\.$'), '');

    return '$a $operationSymbol $b = $resultStr';
  }
}
