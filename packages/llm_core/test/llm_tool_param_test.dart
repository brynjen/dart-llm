import 'package:llm_core/llm_core.dart';
import 'package:test/test.dart';

void main() {
  group('LLMToolParam.toJsonSchema', () {
    test('string type', () {
      final param = LLMToolParam(
        name: 'name',
        type: 'string',
        description: 'A name',
      );

      final schema = param.toJsonSchema();

      expect(schema['type'], 'string');
      expect(schema['description'], 'A name');
      expect(schema.containsKey('enum'), false);
    });

    test('integer type', () {
      final param = LLMToolParam(
        name: 'count',
        type: 'integer',
        description: 'A count',
      );

      final schema = param.toJsonSchema();

      expect(schema['type'], 'integer');
      expect(schema['description'], 'A count');
    });

    test('number type', () {
      final param = LLMToolParam(
        name: 'price',
        type: 'number',
        description: 'A price',
      );

      final schema = param.toJsonSchema();

      expect(schema['type'], 'number');
      expect(schema['description'], 'A price');
    });

    test('boolean type', () {
      final param = LLMToolParam(
        name: 'enabled',
        type: 'boolean',
        description: 'Whether enabled',
      );

      final schema = param.toJsonSchema();

      expect(schema['type'], 'boolean');
      expect(schema['description'], 'Whether enabled');
    });

    test('string with enum values', () {
      final param = LLMToolParam(
        name: 'status',
        type: 'string',
        description: 'Status',
        enums: ['active', 'inactive', 'pending'],
      );

      final schema = param.toJsonSchema();

      expect(schema['type'], 'string');
      expect(schema['enum'], ['active', 'inactive', 'pending']);
    });

    test('array type with items schema', () {
      final param = LLMToolParam(
        name: 'tags',
        type: 'array',
        description: 'Tags',
        items: LLMToolParam(
          name: 'tag',
          type: 'string',
          description: 'A tag',
        ),
      );

      final schema = param.toJsonSchema();

      expect(schema['type'], 'array');
      expect(schema['items'], isA<Map>());
      expect(schema['items']['type'], 'string');
    });

    test('array type without items schema throws', () {
      final param = LLMToolParam(
        name: 'tags',
        type: 'array',
        description: 'Tags',
      );

      expect(
        () => param.toJsonSchema(),
        throwsA(isA<StateError>()),
      );
    });

    test('array with minItems and maxItems', () {
      final param = LLMToolParam(
        name: 'items',
        type: 'array',
        description: 'Items',
        items: LLMToolParam(
          name: 'item',
          type: 'string',
          description: 'An item',
        ),
        minItems: 1,
        maxItems: 10,
      );

      final schema = param.toJsonSchema();

      expect(schema['minItems'], 1);
      expect(schema['maxItems'], 10);
    });

    test('array with uniqueItems', () {
      final param = LLMToolParam(
        name: 'items',
        type: 'array',
        description: 'Items',
        items: LLMToolParam(
          name: 'item',
          type: 'string',
          description: 'An item',
        ),
        uniqueItems: true,
      );

      final schema = param.toJsonSchema();

      expect(schema['uniqueItems'], true);
    });

    test('array with uniqueItems false does not include it', () {
      final param = LLMToolParam(
        name: 'items',
        type: 'array',
        description: 'Items',
        items: LLMToolParam(
          name: 'item',
          type: 'string',
          description: 'An item',
        ),
        uniqueItems: false,
      );

      final schema = param.toJsonSchema();

      expect(schema.containsKey('uniqueItems'), false);
    });

    test('object type with properties', () {
      final param = LLMToolParam(
        name: 'user',
        type: 'object',
        description: 'User object',
        properties: [
          LLMToolParam(
            name: 'name',
            type: 'string',
            description: 'Name',
            isRequired: true,
          ),
          LLMToolParam(
            name: 'age',
            type: 'integer',
            description: 'Age',
            isRequired: false,
          ),
        ],
      );

      final schema = param.toJsonSchema();

      expect(schema['type'], 'object');
      expect(schema['properties'], isA<Map>());
      expect(schema['properties']['name']['type'], 'string');
      expect(schema['properties']['age']['type'], 'integer');
      expect(schema['required'], ['name']);
    });

    test('object type with empty properties', () {
      final param = LLMToolParam(
        name: 'empty',
        type: 'object',
        description: 'Empty object',
        properties: [],
      );

      final schema = param.toJsonSchema();

      expect(schema['type'], 'object');
      expect(schema['properties'], isEmpty);
      expect(schema.containsKey('required'), false);
    });

    test('object type with null properties', () {
      final param = LLMToolParam(
        name: 'empty',
        type: 'object',
        description: 'Empty object',
        properties: null,
      );

      final schema = param.toJsonSchema();

      expect(schema['type'], 'object');
      expect(schema.containsKey('properties'), false);
    });

    test('object with additionalProperties true', () {
      final param = LLMToolParam(
        name: 'config',
        type: 'object',
        description: 'Config',
        additionalProperties: true,
      );

      final schema = param.toJsonSchema();

      expect(schema['additionalProperties'], true);
    });

    test('object with additionalProperties false', () {
      final param = LLMToolParam(
        name: 'config',
        type: 'object',
        description: 'Config',
        additionalProperties: false,
      );

      final schema = param.toJsonSchema();

      expect(schema['additionalProperties'], false);
    });

    test('nested object', () {
      final param = LLMToolParam(
        name: 'nested',
        type: 'object',
        description: 'Nested object',
        properties: [
          LLMToolParam(
            name: 'inner',
            type: 'object',
            description: 'Inner object',
            properties: [
              LLMToolParam(
                name: 'value',
                type: 'string',
                description: 'Value',
              ),
            ],
          ),
        ],
      );

      final schema = param.toJsonSchema();

      expect(schema['type'], 'object');
      expect(schema['properties']['inner']['type'], 'object');
      expect(schema['properties']['inner']['properties']['value']['type'], 'string');
    });

    test('nested array', () {
      final param = LLMToolParam(
        name: 'matrix',
        type: 'array',
        description: 'Matrix',
        items: LLMToolParam(
          name: 'row',
          type: 'array',
          description: 'Row',
          items: LLMToolParam(
            name: 'cell',
            type: 'number',
            description: 'Cell',
          ),
        ),
      );

      final schema = param.toJsonSchema();

      expect(schema['type'], 'array');
      expect(schema['items']['type'], 'array');
      expect(schema['items']['items']['type'], 'number');
    });

    test('array of objects', () {
      final param = LLMToolParam(
        name: 'users',
        type: 'array',
        description: 'Users',
        items: LLMToolParam(
          name: 'user',
          type: 'object',
          description: 'User',
          properties: [
            LLMToolParam(
              name: 'name',
              type: 'string',
              description: 'Name',
            ),
          ],
        ),
      );

      final schema = param.toJsonSchema();

      expect(schema['type'], 'array');
      expect(schema['items']['type'], 'object');
      expect(schema['items']['properties']['name']['type'], 'string');
    });
  });
}
