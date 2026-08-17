# dart-llm — working notes for Claude

## Integration tests that cost money — run only when influenced

The integration suites for **llm_chatgpt, llm_claude, and llm_gemini** hit paid
APIs (keys live in each package's gitignored `.env`). Do **not** run them as a
matter of routine. Run a paid package's integration tests only when the change
actually influences it:

- code changes inside that package, or
- changes to **llm_core** (contracts, merger, tool executor, HTTP helpers —
  everything flows through it), or
- a cross-cutting change that alters what those packages put on the wire.

Doc-only, test-only-elsewhere, or unrelated-package changes do not warrant a
paid run. Unit tests (`melos run test:unit`) are free and always fine.

When a paid run is warranted:
- run `--concurrency=1`;
- **llm_gemini is free-tier: 15 requests/minute** — run one test file at a
  time with ~75s pauses between files, never the whole suite at once;
- llm_vllm (192.168.0.74:8000/8001) and llm_ollama (localhost) are self-hosted
  and free to test.
