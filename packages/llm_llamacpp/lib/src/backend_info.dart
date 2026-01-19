import 'dart:io';

/// Compute backend information.
class BackendInfo {
  BackendInfo({
    required this.name,
    required this.isAvailable,
    this.deviceName,
    this.memoryTotal,
    this.memoryFree,
  });

  /// Backend name (e.g., 'CUDA', 'Metal', 'CPU').
  final String name;

  /// Whether this backend is available.
  final bool isAvailable;

  /// Device name (e.g., 'NVIDIA GeForce RTX 5090').
  final String? deviceName;

  /// Total memory in bytes.
  final int? memoryTotal;

  /// Free memory in bytes.
  final int? memoryFree;

  @override
  String toString() {
    if (!isAvailable) return 'BackendInfo($name: unavailable)';
    final device = deviceName ?? 'unknown device';
    final mem = memoryTotal != null
        ? ' ${(memoryTotal! / 1024 / 1024 / 1024).toStringAsFixed(1)}GB'
        : '';
    return 'BackendInfo($name: $device$mem)';
  }
}

/// Utility functions for detecting system backends.
class BackendDetector {
  /// Get available compute backends.
  static List<BackendInfo> getAvailableBackends() {
    final backends = <BackendInfo>[];

    // CPU is always available
    backends.add(BackendInfo(
      name: 'CPU',
      isAvailable: true,
      deviceName: Platform.operatingSystem,
    ));

    // Check for CUDA (Linux/Windows)
    if (Platform.isLinux || Platform.isWindows) {
      final hasCuda = _checkCudaAvailable();
      backends.add(BackendInfo(
        name: 'CUDA',
        isAvailable: hasCuda,
        deviceName: hasCuda ? _getCudaDeviceName() : null,
      ));
    }

    // Check for Metal (macOS)
    if (Platform.isMacOS) {
      backends.add(BackendInfo(
        name: 'Metal',
        isAvailable: true, // Metal is always available on modern macOS
        deviceName: 'Apple Silicon / AMD GPU',
      ));
    }

    // Check for Vulkan
    final hasVulkan = _checkVulkanAvailable();
    backends.add(BackendInfo(
      name: 'Vulkan',
      isAvailable: hasVulkan,
    ));

    return backends;
  }

  /// Get the default model cache directory.
  static String getDefaultCacheDirectory() {
    final home = Platform.environment['HOME'] ?? '';
    if (Platform.isLinux || Platform.isMacOS) {
      return '$home/.cache/llm_llamacpp/models';
    } else if (Platform.isWindows) {
      final appData = Platform.environment['LOCALAPPDATA'] ?? '';
      return '$appData/llm_llamacpp/models';
    }
    return '$home/.cache/llm_llamacpp/models';
  }

  /// Get the default number of GPU layers based on system.
  static int getRecommendedGpuLayers() {
    final backends = getAvailableBackends();
    if (backends.any((b) => b.name == 'CUDA' && b.isAvailable)) {
      return 99; // Offload all layers
    }
    if (backends.any((b) => b.name == 'Metal' && b.isAvailable)) {
      return 99; // Offload all layers
    }
    return 0; // CPU only
  }

  static bool _checkCudaAvailable() {
    // Check for CUDA libraries
    final cudaPaths = [
      '/usr/local/cuda/lib64/libcudart.so',
      '/usr/lib/x86_64-linux-gnu/libcuda.so',
      '/usr/lib/libcuda.so',
    ];

    for (final path in cudaPaths) {
      if (File(path).existsSync()) return true;
    }

    // Check nvidia-smi
    try {
      final result = Process.runSync('nvidia-smi', ['--query']);
      return result.exitCode == 0;
    } catch (e) {
      return false;
    }
  }

  static String? _getCudaDeviceName() {
    try {
      final result = Process.runSync(
        'nvidia-smi',
        ['--query-gpu=name', '--format=csv,noheader'],
      );
      if (result.exitCode == 0) {
        return (result.stdout as String).trim().split('\n').first;
      }
    } catch (e) {
      // nvidia-smi not available
    }
    return null;
  }

  static bool _checkVulkanAvailable() {
    // Check for Vulkan libraries
    final vulkanPaths = [
      '/usr/lib/x86_64-linux-gnu/libvulkan.so.1',
      '/usr/lib/libvulkan.so.1',
    ];

    for (final path in vulkanPaths) {
      if (File(path).existsSync()) return true;
    }

    return false;
  }
}
