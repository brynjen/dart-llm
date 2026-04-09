import 'dart:convert';

import 'package:llm_core/llm_core.dart';
import 'package:llm_llamacpp/src/isolate_messages.dart';
import 'package:llm_llamacpp/src/response_format_injector.dart';
import 'package:test/test.dart';

void main() {
  group('injectResponseFormat', () {
    final userMsg = IsolateMessage(role: 'user', content: 'Hello');

    test('null format returns original list unchanged', () {
      final messages = [userMsg];
      final result = injectResponseFormat(messages, null);
      expect(identical(result, messages), isTrue);
    });

    test('JsonFormat prepends system message when none exists', () {
      final result = injectResponseFormat([userMsg], const JsonFormat());
      expect(result.length, 2);
      expect(result[0].role, 'system');
      expect(result[0].content, contains('valid JSON'));
      expect(result[1].role, 'user');
    });

    test('JsonFormat appends instruction to existing system message', () {
      final sysMsg = IsolateMessage(role: 'system', content: 'Be concise.');
      final result = injectResponseFormat([sysMsg, userMsg], const JsonFormat());
      expect(result.length, 2);
      expect(result[0].role, 'system');
      expect(result[0].content, startsWith('Be concise.'));
      expect(result[0].content, contains('valid JSON'));
    });

    test('JsonSchemaFormat prepends system message when none exists', () {
      final schema = {'type': 'object', 'properties': {}};
      const format = JsonSchemaFormat(name: 'MyOutput', schema: {'type': 'object', 'properties': {}});
      final result = injectResponseFormat([userMsg], format);
      expect(result.length, 2);
      expect(result[0].role, 'system');
      expect(result[0].content, contains(json.encode(schema)));
    });

    test('JsonSchemaFormat appends to existing system message', () {
      final sysMsg = IsolateMessage(role: 'system', content: 'Original.');
      const format = JsonSchemaFormat(name: 'X', schema: {'type': 'string'});
      final result = injectResponseFormat([sysMsg, userMsg], format);
      expect(result.length, 2);
      expect(result[0].content, startsWith('Original.'));
      expect(result[0].content, contains(json.encode({'type': 'string'})));
    });

    test('original list is not mutated', () {
      final sysMsg = IsolateMessage(role: 'system', content: 'Original.');
      final messages = [sysMsg, userMsg];
      injectResponseFormat(messages, const JsonFormat());
      expect(messages[0].content, 'Original.');
      expect(messages.length, 2);
    });
  });
}
