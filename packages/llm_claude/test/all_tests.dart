import 'unit/claude_model_features_test.dart' as model_features;
import 'unit/claude_request_shape_test.dart' as request_shape;
import 'unit/claude_chat_repository_builder_test.dart' as builder;
import 'unit/claude_chat_repository_test.dart' as chat_repository;
import 'unit/claude_dto_test.dart' as dto;
import 'unit/claude_message_converter_test.dart' as message_converter;
import 'unit/claude_retry_test.dart' as retry;
import 'unit/claude_stream_converter_test.dart' as stream_converter;
import 'integration/all_integration_tests.dart' as integration;

void main() {
  model_features.main();
  request_shape.main();
  builder.main();
  chat_repository.main();
  dto.main();
  message_converter.main();
  retry.main();
  stream_converter.main();
  integration.main();
}
