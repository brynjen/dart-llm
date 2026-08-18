import 'package:example_app/tools/calculator_tool.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('CalculatorTool result formatting', () {
    late CalculatorTool tool;

    setUp(() => tool = CalculatorTool());

    Future<String> run(String operation, dynamic a, dynamic b) =>
        tool.execute({'operation': operation, 'a': a, 'b': b});

    test('integral operands and results carry no fractional part', () async {
      // Regression: the tool widens everything to double for the arithmetic and
      // used to echo that back as "347.0 x 89.0 = 30883". Handing a small model a
      // decimal-looking operand next to an integer-looking answer invited it to
      // restate the result with invented separators ("3,088,83").
      expect(await run('multiply', 347, 89), '347 × 89 = 30883');
      expect(await run('multiply', 2, 2), '2 × 2 = 4');
      expect(await run('add', 1000, 234), '1000 + 234 = 1234');
      expect(await run('multiply', 1020, 10), '1020 × 10 = 10200');
      expect(await run('subtract', 5, 12), '5 - 12 = -7');
    });

    test('never inserts thousands separators', () async {
      final result = await run('multiply', 1000000, 1000);

      expect(result, '1000000 × 1000 = 1000000000');
      expect(result, isNot(contains(',')));
    });

    test('genuine decimals are preserved', () async {
      expect(await run('divide', 10, 4), '10 ÷ 4 = 2.5');
      expect(await run('divide', 7, 2), '7 ÷ 2 = 3.5');
      expect(await run('add', 100.5, 0.25), '100.5 + 0.25 = 100.75');
    });

    test(
      'repeating decimals are truncated, not left with trailing zeros',
      () async {
        expect(await run('divide', 1, 3), '1 ÷ 3 = 0.3333');
      },
    );

    test('numeric strings are accepted, since models quote numbers', () async {
      expect(await run('multiply', '347', '89'), '347 × 89 = 30883');
    });

    test('very large integral values do not lose digits', () async {
      // Past 2^53 a double cannot represent consecutive integers, so the
      // integral fast path is bypassed; the output must still be digits only.
      final result = await run('multiply', 1e15, 10);

      expect(result, isNot(contains('.')));
      expect(result, isNot(contains('e')));
    });

    test(
      'reports bad arguments back to the model instead of throwing',
      () async {
        expect(
          await run('multiply', 'abc', 2),
          contains('must both be numbers'),
        );
        expect(await run('divide', 1, 0), contains('divide by zero'));
        expect(await run('frobnicate', 1, 2), contains('Unknown operation'));
        expect(
          await tool.execute({'a': 1, 'b': 2}),
          contains('missing or non-string'),
        );
      },
    );

    test('onInvoke reports the arguments and the result it returned', () async {
      Map<String, dynamic>? seenArgs;
      String? seenResult;
      final reporting = CalculatorTool(
        onInvoke: (args, result) {
          seenArgs = args;
          seenResult = result;
        },
      );

      final returned = await reporting.execute({
        'operation': 'multiply',
        'a': 347,
        'b': 89,
      });

      expect(seenArgs, {'operation': 'multiply', 'a': 347, 'b': 89});
      expect(seenResult, returned);
      expect(seenResult, '347 × 89 = 30883');
    });
  });
}
