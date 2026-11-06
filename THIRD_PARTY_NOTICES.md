# Third-party notices

Waldo itself is licensed under the GNU General Public License v3.0 (see `LICENSE`). It builds on:

| Project | Use | License |
|---|---|---|
| [llama.cpp](https://github.com/ggml-org/llama.cpp) | Runs the model. Prebuilt xcframework downloaded at build time. | MIT |
| [KeyboardShortcuts](https://github.com/sindresorhus/KeyboardShortcuts) | Global hotkeys. Patched copy in `Vendor/KeyboardShortcuts`. | MIT (`Vendor/KeyboardShortcuts/license`) |
| [Qwen3.5](https://huggingface.co/Qwen/Qwen3.5-4B) | Default model. Not in this repository: the app downloads it from Hugging Face when you ask it to. GGUF builds by [Unsloth](https://huggingface.co/unsloth). | Apache-2.0 |
