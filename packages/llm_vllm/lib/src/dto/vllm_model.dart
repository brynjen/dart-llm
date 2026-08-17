/// Response from vLLM's OpenAI-compatible `/v1/models` endpoint.
class VLLMModelsResponse {
  VLLMModelsResponse({required this.data});

  final String object = 'list';
  final List<VLLMModel> data;

  factory VLLMModelsResponse.fromJson(Map<String, dynamic> json) {
    return VLLMModelsResponse(
      data: (json['data'] as List<dynamic>? ?? const [])
          .map((model) => VLLMModel.fromJson(model as Map<String, dynamic>))
          .toList(growable: false),
    );
  }

  Map<String, dynamic> toJson() => {
    'object': object,
    'data': data.map((model) => model.toJson()).toList(growable: false),
  };
}

/// Represents a model served by vLLM.
class VLLMModel {
  VLLMModel({
    required this.id,
    this.created,
    this.ownedBy,
    this.root,
    this.parent,
    this.maxModelLen,
    this.permission,
  });

  /// Model identifier used in chat and embedding requests.
  final String id;

  /// Alias kept for parity with other providers' model DTOs.
  String get name => id;

  final String object = 'model';
  final int? created;
  final String? ownedBy;
  final String? root;
  final String? parent;

  /// The deployment's context window (`--max-model-len`), in tokens.
  ///
  /// A vLLM extension to the OpenAI model object; this is the *served*
  /// limit, which may be smaller than what the model architecture supports.
  final int? maxModelLen;

  final List<dynamic>? permission;

  factory VLLMModel.fromJson(Map<String, dynamic> json) {
    return VLLMModel(
      id: json['id'] as String? ?? json['name'] as String? ?? '',
      created: json['created'] as int?,
      ownedBy: json['owned_by'] as String?,
      root: json['root'] as String?,
      parent: json['parent'] as String?,
      maxModelLen: json['max_model_len'] as int?,
      permission: json['permission'] as List<dynamic>?,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'object': object,
    if (created != null) 'created': created,
    if (ownedBy != null) 'owned_by': ownedBy,
    if (root != null) 'root': root,
    if (parent != null) 'parent': parent,
    if (maxModelLen != null) 'max_model_len': maxModelLen,
    if (permission != null) 'permission': permission,
  };

  @override
  String toString() => 'VLLMModel(id: $id, maxModelLen: $maxModelLen)';
}
