import 'unit/gemini_chat_repository_builder_test.dart' as builder;
import 'unit/gemini_chat_repository_test.dart' as chat_repository;
import 'unit/gemini_dto_test.dart' as dto;
import 'unit/gemini_message_converter_test.dart' as message_converter;
import 'unit/gemini_retry_test.dart' as retry;
import 'unit/gemini_stream_converter_test.dart' as stream_converter;
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
