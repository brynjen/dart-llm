/// Represents a parameter for an LLM tool.
///
/// Supports JSON Schema types: string, integer, number, boolean, object, array.
class LLMToolParam {
  LLMToolParam({
    required this.name,
    required this.type,
    required this.description,
    this.isRequired = false,
    this.enums = const [],
    this.items,
    this.properties,
    this.additionalProperties,
    this.minItems,
    this.maxItems,
    this.uniqueItems,
    this.minimum,
    this.maximum,
  });

  /// The parameter name.
  final String name;

  /// The JSON Schema type: "string", "integer", "number", "boolean", "object", "array".
  final String type;

  /// A description of the parameter.
  final String description;

  /// Whether this parameter is required.
  final bool isRequired;

  /// Allowed values for enum types.
  final List<String> enums;

  /// For type=="array", describes each element.
  final LLMToolParam? items;

  /// For type=="object", these are its child properties.
  final List<LLMToolParam>? properties;

  /// For type=="object", whether to allow extra fields.
  final bool? additionalProperties;

  /// Minimum number of items for arrays.
  final int? minItems;

  /// Maximum number of items for arrays.
  final int? maxItems;

  /// Whether array items must be unique.
  final bool? uniqueItems;

  /// Smallest value accepted, for `integer` and `number` parameters.
  ///
  /// Emitted as JSON Schema `minimum` (inclusive). Ignored for every other
  /// [type]: `minimum` has no meaning beside a string or a boolean, and a
  /// model reading one there is being told something false. Use
  /// [minItems]/[maxItems] to bound an array's length.
  ///
  /// A bound is a contract, not a guard. A model can satisfy `minimum: 0,
  /// maximum: 1000` and still pass a number from the wrong coordinate space,
  /// so a tool that cares must still validate on execution.
  final num? minimum;

  /// Largest value accepted, for `integer` and `number` parameters.
  ///
  /// Emitted as JSON Schema `maximum` (inclusive). See [minimum].
  final num? maximum;

  /// Converts this parameter to a JSON Schema representation.
  Map<String, dynamic> toJsonSchema() {
    final schema = <String, dynamic>{'description': description};

    switch (type) {
      case 'array':
        schema['type'] = 'array';
        if (items == null) {
          throw StateError('Array param \'$name\' needs an `items` schema');
        }
        schema['items'] = items!.toJsonSchema();
        if (minItems != null) schema['minItems'] = minItems;
        if (maxItems != null) schema['maxItems'] = maxItems;
        if (uniqueItems ?? false) schema['uniqueItems'] = true;
        break;

      case 'object':
        schema['type'] = 'object';
        if (properties != null && properties!.isNotEmpty) {
          schema['properties'] = {
            for (final p in properties!) p.name: p.toJsonSchema(),
          };
          final req = [
            for (final p in properties!)
              if (p.isRequired) p.name,
          ];
          if (req.isNotEmpty) schema['required'] = req;
        }
        if (additionalProperties != null) {
          schema['additionalProperties'] = additionalProperties;
        }
        break;

      default:
        schema['type'] = type;
        if (enums.isNotEmpty) {
          schema['enum'] = enums;
        }
        if (type == 'integer' || type == 'number') {
          if (minimum != null) schema['minimum'] = _bound(minimum!);
          if (maximum != null) schema['maximum'] = _bound(maximum!);
        }
    }

    return schema;
  }

  /// Narrows an integral bound to `int` when [type] is `integer`.
  ///
  /// `jsonEncode` writes a Dart `double` as `2.0`, and validators that take
  /// JSON Schema literally reject a fractional bound on an integer type. The
  /// field is [num] so a `number` parameter can be bounded fractionally, so the
  /// narrowing happens here rather than at the field.
  Object _bound(num value) {
    if (type == 'integer' &&
        value is double &&
        value == value.roundToDouble()) {
      return value.toInt();
    }
    return value;
  }
}
