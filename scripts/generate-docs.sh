#!/bin/bash
# Generate API documentation for all packages using dartdoc

set -e

echo "Generating API documentation..."

# Install dartdoc if not already installed
dart pub global activate dartdoc

# Generate docs for each package
PACKAGES=("llm_core" "llm_ollama" "llm_chatgpt" "llm_llamacpp")

for package in "${PACKAGES[@]}"; do
  echo "Generating docs for $package..."
  cd "packages/$package"
  
  # Skip llm_llamacpp if Flutter is not available
  if [ "$package" = "llm_llamacpp" ] && ! command -v flutter &> /dev/null; then
    echo "Skipping $package (Flutter not available)"
    cd ../..
    continue
  fi
  
  dart pub get
  dart pub global run dartdoc --output=doc/api
  
  # Create index page if it doesn't exist
  if [ ! -f "doc/api/index.html" ]; then
    echo "Warning: Documentation not generated for $package"
  fi
  
  cd ../..
done

echo "Documentation generation complete!"
echo "Documentation is available in packages/*/doc/api/"
