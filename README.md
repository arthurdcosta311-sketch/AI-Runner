# AI Runner

A private, on-device AI runner for iOS. Load any GGUF model file, chat with it locally, let it read the web, and generate images when the AI backend supports it.

- **Chat** — streams responses from a local GGUF model (llama.cpp via SwiftLlama, Metal-accelerated).
- **Models** — download GGUF files from a URL (Hugging Face supported, gated models too) or import them from Files; all stored on-device.
- **Web access** — when enabled, the model can request pages with a `FETCH <url>` command; the app downloads them and feeds the text back into the conversation.
- **Image** — text-to-image through the Hugging Face Inference API (only when a token is set; a local GGUF model can't paint).
- **Settings** — prompt template, context size, temperature, response length, Hugging Face token status, and an optional **JIT — extended memory debugging** toggle (memory-footprint tracking, memory-map diagnostics, JIT availability check).

## Hugging Face token

Add your token the first time the app runs (Settings shows whether it is set). It is stored in the keychain and used for model downloads and image generation. Create one at https://huggingface.co/settings/tokens.

## Builds

GitHub Actions builds the app on every push to `main`: the unsigned IPA is uploaded to the run's **Actions** tab as an artifact and attached to an automatically created **Release** (e.g. `build-42`).

## Development

Open `AI Runner.xcodeproj` in Xcode, or build with the run button in the app you use.

## License

MIT — see [LICENSE](LICENSE).