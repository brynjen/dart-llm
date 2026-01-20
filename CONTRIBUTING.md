# Contributing to Dart LLM

Thank you for your interest in contributing to Dart LLM! This document provides guidelines and instructions for contributing to the project.

## Table of Contents

- [Code of Conduct](#code-of-conduct)
- [Getting Started](#getting-started)
- [Development Setup](#development-setup)
- [Project Structure](#project-structure)
- [Making Changes](#making-changes)
- [Testing](#testing)
- [Code Style](#code-style)
- [Submitting Changes](#submitting-changes)
- [Release Process](#release-process)

## Code of Conduct

This project adheres to a code of conduct that all contributors are expected to follow. Please be respectful and constructive in all interactions.

## Getting Started

1. **Fork the repository** on GitHub
2. **Clone your fork** locally:
   ```bash
   git clone https://github.com/your-username/dart-llm.git
   cd dart-llm
   ```
3. **Add the upstream remote**:
   ```bash
   git remote add upstream https://github.com/brynjen/dart-llm.git
   ```

## Development Setup

### Prerequisites

- **Dart SDK**: Version 3.8.0 or higher
- **Flutter SDK**: Version 3.24.0 or higher (for `llm_llamacpp` package)
- **Git**: For version control
- **Melos**: For monorepo management (optional but recommended)

### Installing Melos

Melos helps manage the monorepo:

```bash
dart pub global activate melos
```

### Initial Setup

1. **Install dependencies** for all packages:
   ```bash
   # Using Melos (recommended)
   melos bootstrap
   
   # Or manually
   cd packages/llm_core && dart pub get
   cd ../llm_ollama && dart pub get
   cd ../llm_chatgpt && dart pub get
   cd ../llm_llamacpp && dart pub get
   ```

2. **Verify setup**:
   ```bash
   # Run all tests
   melos test
   
   # Or manually
   cd packages/llm_core && dart test
   cd ../llm_ollama && dart test
   cd ../llm_chatgpt && dart test
   ```

## Project Structure

This is a monorepo containing multiple packages:

```
dart-llm/
├── packages/
│   ├── llm_core/          # Core abstractions and interfaces
│   ├── llm_ollama/        # Ollama backend implementation
│   ├── llm_chatgpt/       # OpenAI/ChatGPT backend implementation
│   └── llm_llamacpp/      # llama.cpp local inference backend
├── .github/
│   └── workflows/         # CI/CD workflows
├── melos.yaml            # Melos configuration
└── README.md             # Main project documentation
```

### Package Dependencies

- `llm_core`: No dependencies on other packages (base package)
- `llm_ollama`: Depends on `llm_core`
- `llm_chatgpt`: Depends on `llm_core`
- `llm_llamacpp`: Depends on `llm_core`

## Making Changes

### Creating a Branch

1. **Update your fork**:
   ```bash
   git checkout main
   git pull upstream main
   ```

2. **Create a feature branch**:
   ```bash
   git checkout -b feature/your-feature-name
   # or
   git checkout -b fix/your-bug-fix
   ```

### Development Workflow

1. **Make your changes** in the appropriate package(s)
2. **Run tests** to ensure nothing breaks:
   ```bash
   melos test
   ```
3. **Check code formatting**:
   ```bash
   melos format:check
   ```
4. **Run static analysis**:
   ```bash
   melos analyze
   ```

## Testing

### Running Tests

```bash
# Run all tests
melos test

# Run tests for a specific package
cd packages/llm_core && dart test

# Run tests with coverage
cd packages/llm_core && dart test --coverage=coverage
```

### Writing Tests

- **Unit tests**: Test individual functions and classes
- **Integration tests**: Test interactions between components
- **Test files**: Should be in the `test/` directory with `_test.dart` suffix
- **Test organization**: Group related tests using `group()` function

Example test structure:

```dart
import 'package:test/test.dart';
import 'package:llm_core/llm_core.dart';

void main() {
  group('FeatureName', () {
    test('should do something', () {
      // Arrange
      final repository = MockLLMChatRepository();
      
      // Act
      final result = repository.someMethod();
      
      // Assert
      expect(result, isNotNull);
    });
  });
}
```

### Test Coverage

We aim for high test coverage. When adding new features:
- Write tests for new functionality
- Ensure edge cases are covered
- Test error conditions

## Code Style

### Formatting

We use `dart format` for consistent code formatting:

```bash
# Format all code
melos format

# Check formatting
melos format:check
```

### Linting

We use the `lints` package with recommended rules. Run:

```bash
melos analyze
```

### Style Guidelines

1. **Documentation**: Add doc comments for public APIs
   ```dart
   /// Creates a new chat repository.
   ///
   /// [baseUrl] is the base URL for the API.
   /// Returns a configured repository instance.
   LLMChatRepository createRepository(String baseUrl);
   ```

2. **Naming**:
   - Use descriptive names
   - Follow Dart naming conventions
   - Use `camelCase` for variables and functions
   - Use `PascalCase` for classes

3. **Imports**: Organize imports:
   ```dart
   // Dart SDK imports
   import 'dart:async';
   
   // Package imports
   import 'package:http/http.dart';
   
   // Relative imports
   import 'src/helper.dart';
   ```

4. **Error Handling**: Use appropriate exception types from `llm_core`

## Submitting Changes

### Before Submitting

1. **Ensure all tests pass**:
   ```bash
   melos test
   ```

2. **Verify formatting**:
   ```bash
   melos format:check
   ```

3. **Run static analysis**:
   ```bash
   melos analyze
   ```

4. **Update documentation** if needed:
   - Update README.md if adding features
   - Add/update doc comments
   - Update CHANGELOG.md

### Creating a Pull Request

1. **Push your branch** to your fork:
   ```bash
   git push origin feature/your-feature-name
   ```

2. **Create a Pull Request** on GitHub:
   - Use a clear, descriptive title
   - Provide a detailed description
   - Reference any related issues
   - Include examples if adding features

3. **PR Checklist**:
   - [ ] Tests pass
   - [ ] Code is formatted
   - [ ] Static analysis passes
   - [ ] Documentation updated
   - [ ] CHANGELOG.md updated (if applicable)
   - [ ] Breaking changes documented

### PR Review Process

1. **Automated checks** will run via CI
2. **Maintainers** will review your PR
3. **Address feedback** by pushing additional commits
4. **Squash commits** if requested before merging

## Release Process

Releases are managed by maintainers manually:

```bash
# Version bumping (maintainers only)
melos version

# Publishing to pub.dev is done manually by maintainers
# There is no automated publishing workflow
```

### Versioning

We follow [Semantic Versioning](https://semver.org/):
- **MAJOR**: Breaking changes
- **MINOR**: New features (backward compatible)
- **PATCH**: Bug fixes (backward compatible)

## Additional Resources

- [Dart Style Guide](https://dart.dev/guides/language/effective-dart/style)
- [Dart Testing Guide](https://dart.dev/guides/testing)
- [Melos Documentation](https://melos.invertase.dev/)

## Getting Help

- **Issues**: Open an issue for bugs or feature requests
- **Discussions**: Use GitHub Discussions for questions
- **Security**: Report security issues via [Security Policy](SECURITY.md)

Thank you for contributing to Dart LLM! 🎉
