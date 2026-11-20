# AI Runner

A private, on-device AI app for iOS. Chat with a local GGUF language model, let it use tools (web pages, the Focus search engine, HTTP requests, JavaScript and Lua on the phone, GitHub and MCP servers), create images and transcribe audio through Hugging Face, and manage files, all stored on the device.

- **Chat**: streams responses from a local GGUF model (llama.cpp via SwiftLlama). Replies are handled by a dedicated turn runner: one generation at a time, tokens coalesced into about ten UI updates per second instead of one redraw per token, text selection active only on finished messages, and no animated scrolling while a reply streams, because those three were what stalled the screen mid-answer. The prompt is budgeted in tokens, which is what decides how long the model reads before its first word appears. Stop asks the turn to end without cancelling llama.cpp mid-decode, and no reply starts in the background. A running counter shows the turn is alive. Loading runs off the main thread, and loads and replies are gated on free memory. The model is checked before it loads: the app reads the GGUF header, refuses a file that is not a model or that the built-in engine is too old to run (Qwen 3, Llama 4 and other newer architectures), and reports why instead of a bare engine error. The model can use tools by writing one command on its own line. Tools are on by default and can be turned off in Settings. While the keyboard is up, a hide-keyboard button sits in the message bar, and every keyboard has a Hide Keyboard button above it.
  - `FETCH <url>` reads a web page.
  - `SEARCH <query>` searches with the Focus engine (the search engine from Focus Lite).
  - `CURL [GET|POST|HEAD] <url>` makes an HTTP request.
  - `RUN JS` and `RUN LUA`, followed by a code block, run the code on the phone.
  - `GITHUB <api path>` calls the GitHub REST API with your token.
  - `MCP <server> <tool> <json>` calls a tool on an MCP server you added.
- **Models**: download language models from a built-in list (Qwen 2.5, Llama 3.2, Phi-3.5, Gemma 2) or search every GGUF model on Hugging Face. Every listed model loads in the engine the app ships. Downloads have no size limit and stream straight to disk. Model files can also be imported from Files, and one the engine cannot run is marked as such in the list.
- **Create**: images (Stable Diffusion XL, SD 1.5, FLUX) and speech-to-text (Whisper), through the Hugging Face hosted inference API with your token.
- **Browser**: the Focus search engine and a simple web view that keeps no cookies or history, opened from the globe in Chat.
- **Files**: browse, create, edit and delete files in the app's Documents folder, download files from the internet, and import files from the Files app.
- **Projects**: repositories cloned from GitHub, browsed and edited like any folder.
- **Settings**: sign in to GitHub with a personal access token; it shows whether you are signed in, lists your projects and clones any of them into the Projects tab. Also the inference settings, the tools toggle, MCP servers and the developer options.

## Hugging Face token

Add your token in the Models tab. It is stored in the keychain. It is used for gated models, Hugging Face search, and the hosted image and speech models. Create one at https://huggingface.co/settings/tokens.

## Builds

GitHub Actions builds the app on every push to `main`. The unsigned IPA is uploaded to the run's **Actions** tab, and attached to the **v2.4** release on the Releases page, where later builds update the same release.

## Development

Open `AI Runner.xcodeproj` in Xcode, or build with the run button in the app you use.

## License

MIT — see [LICENSE](LICENSE).
