# Security Policy

## Supported Versions

We currently support the following versions with security updates:

| Version | Supported          |
| ------- | ------------------ |
| 0.1.x   | :white_check_mark: |

## Reporting a Vulnerability

If you have discovered a security vulnerability in this project, please report it privately. **Do not disclose it as a public issue.** This gives us time to work with you to fix the issue before public exposure, reducing the chance that the exploit will be used before a patch is released.

### How to Report

Please report security vulnerabilities by:
1. Creating a private [security advisory](https://github.com/brynjen/dart-llm/security/advisories/new) on GitHub
2. Or emailing the maintainers directly (if you have contact information)

### What to Include

Your report should include:
- A clear description of the vulnerability
- Steps to reproduce the issue
- Potential impact assessment
- Suggested fix (if you have one)

### Response Timeline

- **Initial Response**: Within 7 days
- **Status Update**: Within 30 days
- **Fix Timeline**: Depends on severity, but we aim for 90 days or less

## Security Best Practices

### API Keys and Credentials

- **Never commit API keys or credentials** to the repository
- Use environment variables or secure credential storage
- Rotate API keys regularly
- Use the minimum required permissions for API keys

### Network Security

- Always use HTTPS when connecting to LLM APIs
- Validate SSL certificates
- Be cautious when using untrusted networks
- Consider using VPNs for sensitive operations

### Input Validation

- **Always validate and sanitize user inputs** before sending to LLM APIs
- Be aware of prompt injection attacks
- Implement rate limiting for API calls
- Monitor for unusual patterns

### Model Security (llm_llamacpp)

When using local models via `llm_llamacpp`:

- **Only load models from trusted sources**
- Verify model file integrity (checksums/hashes)
- Run untrusted models in isolated environments (sandboxes, containers)
- Be cautious with models that execute code or access system resources

### Data Privacy

- Be mindful of what data you send to LLM APIs
- Consider data retention policies of API providers
- Implement data encryption for sensitive information
- Review privacy policies of backend providers (OpenAI, Ollama, etc.)

### Dependency Security

- Keep dependencies up to date
- Regularly run `dart pub outdated --security`
- Review dependency changes before updating
- Use Dependabot or similar tools for automated updates

## Security Considerations by Backend

### OpenAI/ChatGPT (`llm_chatgpt`)

- API keys are sent over HTTPS
- Review OpenAI's data usage policies
- Be aware of rate limits and quotas
- Monitor API usage for unexpected activity

### Ollama (`llm_ollama`)

- Default installation may be accessible on local network
- Secure your Ollama instance if exposed to network
- Use authentication if available
- Be cautious with remote Ollama instances

### llama.cpp (`llm_llamacpp`)

- Local execution reduces data privacy concerns
- Model files can be large - verify integrity
- GPU acceleration may have security implications
- Isolate model execution when possible

## Covered Topics

Security vulnerabilities in the following areas are considered valid:

- Core package (`llm_core`) - interfaces and abstractions
- Backend implementations (`llm_ollama`, `llm_chatgpt`, `llm_llamacpp`)
- Authentication and credential handling
- Network communication and API interactions
- Input validation and sanitization
- Error handling that could leak sensitive information

### Not Covered

The following are **not** considered security vulnerabilities:

- Issues in dependencies (report to dependency maintainers)
- Issues in llama.cpp submodule (report to [llama.cpp project](https://github.com/ggml-org/llama.cpp))
- Denial of Service (DoS) attacks (unless they exploit a bug)
- Social engineering attacks
- Physical security issues

## Security Updates

Security updates will be:
- Released as patch versions (e.g., 0.1.0 → 0.1.1)
- Documented in CHANGELOG.md
- Announced via GitHub releases
- Backported to supported versions when possible

## Acknowledgments

We appreciate responsible disclosure of security vulnerabilities. Contributors who report valid security issues will be acknowledged (with permission) in security advisories and release notes.
