# AI Runner

A private, on-device AI app for iOS. Chat with a local GGUF language model, let it use tools (web pages, the Focus search engine, HTTP requests, JavaScript and Lua on the phone, GitHub and MCP servers), create images and transcribe audio through Hugging Face, and manage files, all stored on the device.

- **Chat**: streams responses from a local GGUF model (llama.cpp via SwiftLlama, Metal-accelerated). The model can use tools by writing one command on its own line. The app runs it and feeds the result back. Tools are on by default and can be turned off in Settings.
  - `FETCH <url>` reads a web page.
  - `SEARCH <query>` searches with the Focus engine (the search engine from Focus Lite).
  - `CURL [GET|POST|HEAD] <url>` makes an HTTP request.
  - `RUN JS` and `RUN LUA`, followed by a code block, run the code on the phone.
  - `GITHUB <api path>` calls the GitHub REST API with your token.
  - `MCP <server> <tool> <json>` calls a tool on an MCP server you added.
- **Models**: download language models from a built-in list (Qwen, Llama, Gemma) or search every GGUF model on Hugging Face. Downloads have no size cap and stream straight to disk. Model files can also be imported from Files.
- **Create**: images (Stable Diffusion XL, SD 1.5, FLUX) and speech-to-text (Whisper), through the Hugging Face hosted inference API with your token.
- **Browser**: the Focus search engine, and a simple web view that keeps no cookies or history.
- **Files**: browse, create, edit and delete files in the app's Documents folder, download files from the internet, and import files from the Files app.
- **Integrations**: save a GitHub token, and add MCP servers over https.

## Hugging Face token

Add your token in the Models tab. It is stored in the keychain. It is used for gated models, Hugging Face search, and the hosted image and speech models. Create one at https://huggingface.co/settings/tokens.

## Builds

GitHub Actions builds the app on every push to `main`. The unsigned IPA is uploaded to the run's **Actions** tab, and attached to the **v2.0** release on the Releases page, where later builds update the same release.

## Development

Open `AI Runner.xcodeproj` in Xcode, or build with the run button in the app you use.

## License

MIT — see [LICENSE](LICENSE).
