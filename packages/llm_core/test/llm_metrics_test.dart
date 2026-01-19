import 'package:llm_core/llm_core.dart';
import 'package:test/test.dart';

void main() {
  group('DefaultLLMMetrics', () {
    late DefaultLLMMetrics metrics;

    setUp(() {
      metrics = DefaultLLMMetrics();
    });

    test('records requests correctly', () {
      metrics.recordRequest(model: 'gpt-4o', success: true);
      metrics.recordRequest(model: 'gpt-4o', success: false);
      metrics.recordRequest(model: 'gpt-4o', success: true);

      final result = metrics.getMetrics();
      expect(result['gpt-4o.total_requests'], 3);
      expect(result['gpt-4o.successful_requests'], 2);
      expect(result['gpt-4o.failed_requests'], 1);
    });

    test('records latency correctly', () {
      metrics.recordLatency(
        model: 'gpt-4o',
        latency: Duration(milliseconds: 100),
      );
      metrics.recordLatency(
        model: 'gpt-4o',
        latency: Duration(milliseconds: 200),
      );

      final result = metrics.getMetrics();
      expect(result['gpt-4o.avg_latency_ms'], 150.0);
    });

    test('records tokens correctly', () {
      metrics.recordTokens(
        model: 'gpt-4o',
        promptTokens: 10,
        generatedTokens: 20,
      );
      metrics.recordTokens(
        model: 'gpt-4o',
        promptTokens: 15,
        generatedTokens: 25,
      );

      final result = metrics.getMetrics();
      expect(result['gpt-4o.total_prompt_tokens'], 25);
      expect(result['gpt-4o.total_generated_tokens'], 45);
    });

    test('records errors correctly', () {
      metrics.recordError(model: 'gpt-4o', errorType: 'timeout');
      metrics.recordError(model: 'gpt-4o', errorType: 'timeout');
      metrics.recordError(model: 'gpt-4o', errorType: 'api_error');

      final result = metrics.getMetrics();
      final errors = result['gpt-4o.errors'] as Map<String, int>;
      expect(errors['timeout'], 2);
      expect(errors['api_error'], 1);
    });

    test('reset clears all metrics', () {
      metrics.recordRequest(model: 'gpt-4o', success: true);
      metrics.reset();

      final result = metrics.getMetrics();
      expect(result, isEmpty);
    });
  });
}
