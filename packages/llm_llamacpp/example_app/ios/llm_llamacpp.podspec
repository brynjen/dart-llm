Pod::Spec.new do |s|
  s.name             = 'llm_llamacpp'
  s.version          = '0.1.0'
  s.summary          = 'llama.cpp FFI plugin for Flutter'
  s.description      = <<-DESC
llama.cpp backend implementation for LLM interactions. Enables local on-device inference with GGUF models.
                       DESC
  s.homepage         = 'https://github.com/brynjen/dart-llm'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'brynjen' => 'brynjen@example.com' }
  s.source           = { :path => '.' }
  s.source_files     = 'Classes/**/*'
  s.dependency 'Flutter'
  s.platform         = :ios, '12.0'

  # Flutter.framework does not contain a i386 slice.
  s.pod_target_xcconfig = { 
    'DEFINES_MODULE' => 'YES', 
    'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386',
    'OTHER_LDFLAGS' => '-force_load $(PODS_TARGET_SRCROOT)/Frameworks/llama.xcframework/$(PLATFORM_NAME)/libllama_combined.a'
  }
  s.swift_version = '5.0'
  
  # Required frameworks for llama.cpp with Metal support
  s.frameworks = 'Metal', 'MetalKit', 'Accelerate', 'Foundation'

  # Vendored framework containing libllama (static library)
  s.vendored_frameworks = 'Frameworks/llama.xcframework'
  
  # Static library linkage
  s.static_framework = true
end

