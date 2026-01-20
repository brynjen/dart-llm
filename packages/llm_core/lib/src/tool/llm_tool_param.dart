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

  /// Converts this parameter to a JSON Schema representation.
  Map<String, dynamic> toJsonSchema() {
    final schema = <String, dynamic>{"description": description};

    switch (type) {
      case "array":
        schema["type"] = "array";
        if (items == null) {
          throw StateError("Array param '$name' needs an `items` schema");
        }
        schema["items"] = items!.toJsonSchema();
        if (minItems != null) schema["minItems"] = minItems;
        if (maxItems != null) schema["maxItems"] = maxItems;
        if (uniqueItems == true) schema["uniqueItems"] = true;
        break;

      case "object":
        schema["type"] = "object";
        if (properties != null && properties!.isNotEmpty) {
          schema["properties"] = {
            for (var p in properties!) p.name: p.toJsonSchema(),
          };
          final req = [
            for (var p in properties!)
              if (p.isRequired) p.name,
          ];
          if (req.isNotEmpty) schema["required"] = req;
        }
        if (additionalProperties != null) {
          schema["additionalProperties"] = additionalProperties;
        }
        break;

      default:
        schema["type"] = type;
        if (enums.isNotEmpty) {
          schema["enum"] = enums;
        }
    }

    return schema;
  }
}
