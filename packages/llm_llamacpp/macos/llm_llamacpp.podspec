Pod::Spec.new do |s|
  s.name             = 'llm_llamacpp'
  s.version          = '0.1.9'
  s.summary          = 'llama.cpp FFI plugin for Flutter macOS'
  s.description      = <<-DESC
llama.cpp backend implementation for LLM interactions. Enables local
on-device inference with GGUF models on macOS via Native Assets.
                       DESC
  s.homepage         = 'https://github.com/brynjen/dart-llm'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'brynjen' => 'brynjen@example.com' }
  s.source           = { :path => '.' }
  s.source_files     = 'Classes/**/*'
  s.dependency 'FlutterMacOS'
  s.platform         = :osx, '10.14'

  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES' }
  s.swift_version = '5.0'
end
