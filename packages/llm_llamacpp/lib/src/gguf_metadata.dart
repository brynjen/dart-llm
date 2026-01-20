import 'dart:io';
import 'dart:typed_data';

/// GGUF file magic bytes: "GGUF"
const int ggufMagic = 0x46554747; // 'GGUF' in little-endian

/// GGUF metadata types
enum GgufMetadataType {
  uint8(0),
  int8(1),
  uint16(2),
  int16(3),
  uint32(4),
  int32(5),
  float32(6),
  bool_(7),
  string(8),
  array(9),
  uint64(10),
  int64(11),
  float64(12);

  const GgufMetadataType(this.value);
  final int value;

  static GgufMetadataType fromValue(int value) {
    return GgufMetadataType.values.firstWhere(
      (t) => t.value == value,
      orElse: () => throw ArgumentError('Unknown GGUF type: $value'),
    );
  }
}

/// Represents metadata from a GGUF model file.
///
/// This allows reading model information without fully loading the model.
class GgufMetadata {
  GgufMetadata({
    required this.path,
    required this.version,
    required this.tensorCount,
    required this.metadataKvCount,
    required this.metadata,
  });

  /// Path to the GGUF file.
  final String path;

  /// GGUF format version.
  final int version;

  /// Number of tensors in the model.
  final int tensorCount;

  /// Number of metadata key-value pairs.
  final int metadataKvCount;

  /// Metadata key-value pairs.
  final Map<String, dynamic> metadata;

  /// Get a metadata value by key.
  T? get<T>(String key) => metadata[key] as T?;

  /// Get the model architecture (e.g., 'llama', 'qwen2', 'phi3').
  String? get architecture => get<String>('general.architecture');

  /// Get the model name.
  String? get name => get<String>('general.name');

  /// Get the model type.
  String? get type => get<String>('general.type');

  /// Get the quantization type.
  String? get quantizationType {
    final fileType = get<int>('general.file_type');
    if (fileType == null) return null;
    return _fileTypeToQuantization(fileType);
  }

  /// Get the context length the model was trained with.
  int? get contextLength {
    final arch = architecture;
    if (arch == null) return null;
    return get<int>('$arch.context_length');
  }

  /// Get the embedding dimension.
  int? get embeddingLength {
    final arch = architecture;
    if (arch == null) return null;
    return get<int>('$arch.embedding_length');
  }

  /// Get the number of layers/blocks.
  int? get blockCount {
    final arch = architecture;
    if (arch == null) return null;
    return get<int>('$arch.block_count');
  }

  /// Get the number of attention heads.
  int? get headCount {
    final arch = architecture;
    if (arch == null) return null;
    return get<int>('$arch.attention.head_count');
  }

  /// Get the feed-forward hidden size.
  int? get feedForwardLength {
    final arch = architecture;
    if (arch == null) return null;
    return get<int>('$arch.feed_forward_length');
  }

  /// Get the vocabulary size (from tokenizer metadata).
  int? get vocabSize {
    final tokens = get<List>('tokenizer.ggml.tokens');
    return tokens?.length;
  }

  /// Estimate total parameters (rough approximation).
  int? get estimatedParameters {
    final embd = embeddingLength;
    final blocks = blockCount;
    final ff = feedForwardLength;
    final vocab = vocabSize;

    if (embd == null || blocks == null) return null;

    // Rough estimation based on typical transformer architecture
    final ffSize = ff ?? (embd * 4);

    // Per layer: attention (4 * embd^2) + FFN (3 * embd * ff) + norms
    final perLayer = 4 * embd * embd + 3 * embd * ffSize + 2 * embd;

    // Total: layers + embeddings + output
    final total = blocks * perLayer + (vocab ?? 32000) * embd * 2;

    return total;
  }

  /// Get human-readable size string.
  String get sizeLabel {
    final params = estimatedParameters;
    if (params == null) return 'Unknown';

    if (params >= 1e9) {
      return '${(params / 1e9).toStringAsFixed(1)}B';
    } else if (params >= 1e6) {
      return '${(params / 1e6).toStringAsFixed(0)}M';
    } else {
      return '${(params / 1e3).toStringAsFixed(0)}K';
    }
  }

  /// Check if this is a vision/multimodal model.
  bool get isVisionModel {
    final arch = architecture?.toLowerCase() ?? '';
    return arch.contains('vl') ||
        arch.contains('vision') ||
        metadata.keys.any((k) => k.contains('vision') || k.contains('clip'));
  }

  /// Get the file size in bytes.
  int get fileSize => File(path).lengthSync();

  /// Get human-readable file size.
  String get fileSizeLabel {
    final size = fileSize;
    if (size >= 1024 * 1024 * 1024) {
      return '${(size / 1024 / 1024 / 1024).toStringAsFixed(2)} GB';
    } else if (size >= 1024 * 1024) {
      return '${(size / 1024 / 1024).toStringAsFixed(1)} MB';
    } else {
      return '${(size / 1024).toStringAsFixed(0)} KB';
    }
  }

  @override
  String toString() {
    return 'GgufMetadata('
        'name: $name, '
        'arch: $architecture, '
        'params: $sizeLabel, '
        'quant: $quantizationType, '
        'context: $contextLength, '
        'size: $fileSizeLabel'
        ')';
  }

  /// Read GGUF metadata from a file.
  ///
  /// This reads only the header and metadata, not the tensor data.
  static Future<GgufMetadata> fromFile(String path) async {
    final file = File(path);
    if (!await file.exists()) {
      throw FileSystemException('File not found', path);
    }

    final raf = await file.open(mode: FileMode.read);
    try {
      return await _readMetadata(raf, path);
    } finally {
      await raf.close();
    }
  }

  /// Synchronously read GGUF metadata from a file.
  static GgufMetadata fromFileSync(String path) {
    final file = File(path);
    if (!file.existsSync()) {
      throw FileSystemException('File not found', path);
    }

    final raf = file.openSync(mode: FileMode.read);
    try {
      return _readMetadataSync(raf, path);
    } finally {
      raf.closeSync();
    }
  }

  /// Check if a file is a valid GGUF file.
  static bool isValidGguf(String path) {
    final file = File(path);
    if (!file.existsSync()) return false;

    final raf = file.openSync(mode: FileMode.read);
    try {
      final magic = _readUint32Sync(raf);
      return magic == ggufMagic;
    } catch (e) {
      return false;
    } finally {
      raf.closeSync();
    }
  }

  static Future<GgufMetadata> _readMetadata(
    RandomAccessFile raf,
    String path,
  ) async {
    // Read magic
    final magic = await _readUint32(raf);
    if (magic != ggufMagic) {
      throw FormatException('Invalid GGUF magic: 0x${magic.toRadixString(16)}');
    }

    // Read version
    final version = await _readUint32(raf);
    if (version < 2 || version > 3) {
      throw FormatException('Unsupported GGUF version: $version');
    }

    // Read tensor count and metadata count
    final tensorCount = await _readUint64(raf);
    final metadataKvCount = await _readUint64(raf);

    // Read metadata
    final metadata = <String, dynamic>{};
    for (var i = 0; i < metadataKvCount; i++) {
      final key = await _readString(raf);
      final value = await _readValue(raf);
      metadata[key] = value;
    }

    return GgufMetadata(
      path: path,
      version: version,
      tensorCount: tensorCount,
      metadataKvCount: metadataKvCount,
      metadata: metadata,
    );
  }

  static GgufMetadata _readMetadataSync(RandomAccessFile raf, String path) {
    // Read magic
    final magic = _readUint32Sync(raf);
    if (magic != ggufMagic) {
      throw FormatException('Invalid GGUF magic: 0x${magic.toRadixString(16)}');
    }

    // Read version
    final version = _readUint32Sync(raf);
    if (version < 2 || version > 3) {
      throw FormatException('Unsupported GGUF version: $version');
    }

    // Read tensor count and metadata count
    final tensorCount = _readUint64Sync(raf);
    final metadataKvCount = _readUint64Sync(raf);

    // Read metadata
    final metadata = <String, dynamic>{};
    for (var i = 0; i < metadataKvCount; i++) {
      final key = _readStringSync(raf);
      final value = _readValueSync(raf);
      metadata[key] = value;
    }

    return GgufMetadata(
      path: path,
      version: version,
      tensorCount: tensorCount,
      metadataKvCount: metadataKvCount,
      metadata: metadata,
    );
  }

  static Future<int> _readUint32(RandomAccessFile raf) async {
    final bytes = await raf.read(4);
    return ByteData.sublistView(bytes).getUint32(0, Endian.little);
  }

  static int _readUint32Sync(RandomAccessFile raf) {
    final bytes = raf.readSync(4);
    return ByteData.sublistView(bytes).getUint32(0, Endian.little);
  }

  static Future<int> _readUint64(RandomAccessFile raf) async {
    final bytes = await raf.read(8);
    return ByteData.sublistView(bytes).getUint64(0, Endian.little);
  }

  static int _readUint64Sync(RandomAccessFile raf) {
    final bytes = raf.readSync(8);
    return ByteData.sublistView(bytes).getUint64(0, Endian.little);
  }

  static Future<String> _readString(RandomAccessFile raf) async {
    final length = await _readUint64(raf);
    final bytes = await raf.read(length);
    return String.fromCharCodes(bytes);
  }

  static String _readStringSync(RandomAccessFile raf) {
    final length = _readUint64Sync(raf);
    final bytes = raf.readSync(length);
    return String.fromCharCodes(bytes);
  }

  static Future<dynamic> _readValue(RandomAccessFile raf) async {
    final bytes = await raf.read(4);
    final type = GgufMetadataType.fromValue(
      ByteData.sublistView(bytes).getUint32(0, Endian.little),
    );

    switch (type) {
      case GgufMetadataType.uint8:
        return (await raf.read(1))[0];
      case GgufMetadataType.int8:
        return ByteData.sublistView(await raf.read(1)).getInt8(0);
      case GgufMetadataType.uint16:
        return ByteData.sublistView(
          await raf.read(2),
        ).getUint16(0, Endian.little);
      case GgufMetadataType.int16:
        return ByteData.sublistView(
          await raf.read(2),
        ).getInt16(0, Endian.little);
      case GgufMetadataType.uint32:
        return await _readUint32(raf);
      case GgufMetadataType.int32:
        return ByteData.sublistView(
          await raf.read(4),
        ).getInt32(0, Endian.little);
      case GgufMetadataType.float32:
        return ByteData.sublistView(
          await raf.read(4),
        ).getFloat32(0, Endian.little);
      case GgufMetadataType.bool_:
        return (await raf.read(1))[0] != 0;
      case GgufMetadataType.string:
        return await _readString(raf);
      case GgufMetadataType.array:
        final elementType = GgufMetadataType.fromValue(await _readUint32(raf));
        final length = await _readUint64(raf);
        // For large arrays (like tokens), just return the length to save memory
        if (length > 1000) {
          // Skip the array data
          final elementSize = _getElementSize(elementType);
          if (elementSize > 0) {
            await raf.setPosition(await raf.position() + length * elementSize);
          } else {
            // Variable-length elements (strings), skip individually
            for (var i = 0; i < length; i++) {
              await _skipValue(raf, elementType);
            }
          }
          return List.filled(length, null); // Placeholder
        }
        final list = <dynamic>[];
        for (var i = 0; i < length; i++) {
          list.add(await _readTypedValue(raf, elementType));
        }
        return list;
      case GgufMetadataType.uint64:
        return await _readUint64(raf);
      case GgufMetadataType.int64:
        return ByteData.sublistView(
          await raf.read(8),
        ).getInt64(0, Endian.little);
      case GgufMetadataType.float64:
        return ByteData.sublistView(
          await raf.read(8),
        ).getFloat64(0, Endian.little);
    }
  }

  static dynamic _readValueSync(RandomAccessFile raf) {
    final bytes = raf.readSync(4);
    final type = GgufMetadataType.fromValue(
      ByteData.sublistView(bytes).getUint32(0, Endian.little),
    );

    switch (type) {
      case GgufMetadataType.uint8:
        return raf.readSync(1)[0];
      case GgufMetadataType.int8:
        return ByteData.sublistView(raf.readSync(1)).getInt8(0);
      case GgufMetadataType.uint16:
        return ByteData.sublistView(
          raf.readSync(2),
        ).getUint16(0, Endian.little);
      case GgufMetadataType.int16:
        return ByteData.sublistView(raf.readSync(2)).getInt16(0, Endian.little);
      case GgufMetadataType.uint32:
        return _readUint32Sync(raf);
      case GgufMetadataType.int32:
        return ByteData.sublistView(raf.readSync(4)).getInt32(0, Endian.little);
      case GgufMetadataType.float32:
        return ByteData.sublistView(
          raf.readSync(4),
        ).getFloat32(0, Endian.little);
      case GgufMetadataType.bool_:
        return raf.readSync(1)[0] != 0;
      case GgufMetadataType.string:
        return _readStringSync(raf);
      case GgufMetadataType.array:
        final elementType = GgufMetadataType.fromValue(_readUint32Sync(raf));
        final length = _readUint64Sync(raf);
        // For large arrays (like tokens), just return the length to save memory
        if (length > 1000) {
          // Skip the array data
          final elementSize = _getElementSize(elementType);
          if (elementSize > 0) {
            raf.setPositionSync(raf.positionSync() + length * elementSize);
          } else {
            // Variable-length elements (strings), skip individually
            for (var i = 0; i < length; i++) {
              _skipValueSync(raf, elementType);
            }
          }
          return List.filled(length, null); // Placeholder
        }
        final list = <dynamic>[];
        for (var i = 0; i < length; i++) {
          list.add(_readTypedValueSync(raf, elementType));
        }
        return list;
      case GgufMetadataType.uint64:
        return _readUint64Sync(raf);
      case GgufMetadataType.int64:
        return ByteData.sublistView(raf.readSync(8)).getInt64(0, Endian.little);
      case GgufMetadataType.float64:
        return ByteData.sublistView(
          raf.readSync(8),
        ).getFloat64(0, Endian.little);
    }
  }

  static Future<dynamic> _readTypedValue(
    RandomAccessFile raf,
    GgufMetadataType type,
  ) async {
    switch (type) {
      case GgufMetadataType.uint8:
        return (await raf.read(1))[0];
      case GgufMetadataType.int8:
        return ByteData.sublistView(await raf.read(1)).getInt8(0);
      case GgufMetadataType.uint16:
        return ByteData.sublistView(
          await raf.read(2),
        ).getUint16(0, Endian.little);
      case GgufMetadataType.int16:
        return ByteData.sublistView(
          await raf.read(2),
        ).getInt16(0, Endian.little);
      case GgufMetadataType.uint32:
        return await _readUint32(raf);
      case GgufMetadataType.int32:
        return ByteData.sublistView(
          await raf.read(4),
        ).getInt32(0, Endian.little);
      case GgufMetadataType.float32:
        return ByteData.sublistView(
          await raf.read(4),
        ).getFloat32(0, Endian.little);
      case GgufMetadataType.bool_:
        return (await raf.read(1))[0] != 0;
      case GgufMetadataType.string:
        return await _readString(raf);
      case GgufMetadataType.uint64:
        return await _readUint64(raf);
      case GgufMetadataType.int64:
        return ByteData.sublistView(
          await raf.read(8),
        ).getInt64(0, Endian.little);
      case GgufMetadataType.float64:
        return ByteData.sublistView(
          await raf.read(8),
        ).getFloat64(0, Endian.little);
      case GgufMetadataType.array:
        // Nested arrays not supported in metadata
        return null;
    }
  }

  static dynamic _readTypedValueSync(
    RandomAccessFile raf,
    GgufMetadataType type,
  ) {
    switch (type) {
      case GgufMetadataType.uint8:
        return raf.readSync(1)[0];
      case GgufMetadataType.int8:
        return ByteData.sublistView(raf.readSync(1)).getInt8(0);
      case GgufMetadataType.uint16:
        return ByteData.sublistView(
          raf.readSync(2),
        ).getUint16(0, Endian.little);
      case GgufMetadataType.int16:
        return ByteData.sublistView(raf.readSync(2)).getInt16(0, Endian.little);
      case GgufMetadataType.uint32:
        return _readUint32Sync(raf);
      case GgufMetadataType.int32:
        return ByteData.sublistView(raf.readSync(4)).getInt32(0, Endian.little);
      case GgufMetadataType.float32:
        return ByteData.sublistView(
          raf.readSync(4),
        ).getFloat32(0, Endian.little);
      case GgufMetadataType.bool_:
        return raf.readSync(1)[0] != 0;
      case GgufMetadataType.string:
        return _readStringSync(raf);
      case GgufMetadataType.uint64:
        return _readUint64Sync(raf);
      case GgufMetadataType.int64:
        return ByteData.sublistView(raf.readSync(8)).getInt64(0, Endian.little);
      case GgufMetadataType.float64:
        return ByteData.sublistView(
          raf.readSync(8),
        ).getFloat64(0, Endian.little);
      case GgufMetadataType.array:
        // Nested arrays not supported in metadata
        return null;
    }
  }

  static Future<void> _skipValue(
    RandomAccessFile raf,
    GgufMetadataType type,
  ) async {
    final size = _getElementSize(type);
    if (size > 0) {
      await raf.setPosition(await raf.position() + size);
    } else if (type == GgufMetadataType.string) {
      final length = await _readUint64(raf);
      await raf.setPosition(await raf.position() + length);
    }
  }

  static void _skipValueSync(RandomAccessFile raf, GgufMetadataType type) {
    final size = _getElementSize(type);
    if (size > 0) {
      raf.setPositionSync(raf.positionSync() + size);
    } else if (type == GgufMetadataType.string) {
      final length = _readUint64Sync(raf);
      raf.setPositionSync(raf.positionSync() + length);
    }
  }

  static int _getElementSize(GgufMetadataType type) {
    switch (type) {
      case GgufMetadataType.uint8:
      case GgufMetadataType.int8:
      case GgufMetadataType.bool_:
        return 1;
      case GgufMetadataType.uint16:
      case GgufMetadataType.int16:
        return 2;
      case GgufMetadataType.uint32:
      case GgufMetadataType.int32:
      case GgufMetadataType.float32:
        return 4;
      case GgufMetadataType.uint64:
      case GgufMetadataType.int64:
      case GgufMetadataType.float64:
        return 8;
      case GgufMetadataType.string:
      case GgufMetadataType.array:
        return 0; // Variable length
    }
  }

  static String _fileTypeToQuantization(int fileType) {
    const types = {
      0: 'F32',
      1: 'F16',
      2: 'Q4_0',
      3: 'Q4_1',
      6: 'Q5_0',
      7: 'Q5_1',
      8: 'Q8_0',
      9: 'Q8_1',
      10: 'Q2_K',
      11: 'Q3_K_S',
      12: 'Q3_K_M',
      13: 'Q3_K_L',
      14: 'Q4_K_S',
      15: 'Q4_K_M',
      16: 'Q5_K_S',
      17: 'Q5_K_M',
      18: 'Q6_K',
      19: 'IQ2_XXS',
      20: 'IQ2_XS',
      21: 'IQ3_XXS',
      22: 'IQ1_S',
      23: 'IQ4_NL',
      24: 'IQ3_S',
      25: 'IQ2_S',
      26: 'IQ4_XS',
      27: 'IQ1_M',
      28: 'BF16',
    };
    return types[fileType] ?? 'Unknown ($fileType)';
  }
}
