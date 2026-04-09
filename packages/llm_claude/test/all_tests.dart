import 'unit/claude_chat_repository_builder_test.dart' as builder;
import 'unit/claude_chat_repository_test.dart' as chat_repository;
import 'unit/claude_dto_test.dart' as dto;
import 'unit/claude_message_converter_test.dart' as message_converter;
import 'unit/claude_retry_test.dart' as retry;
import 'unit/claude_stream_converter_test.dart' as stream_converter;
import 'integration/all_integration_tests.dart' as integration;

void main() {
  builder.main();
  chat_repository.main();
  dto.main();
  message_converter.main();
  retry.main();
  stream_converter.main();
  integration.main();
}
