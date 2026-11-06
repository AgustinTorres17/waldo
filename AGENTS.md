# Working on Waldo

Waldo is a native macOS app (Swift, SwiftUI, AppKit) that corrects, translates and rephrases text in any app, and answers questions in a chat. The model runs locally with llama.cpp. If you are helping someone change Waldo, assume they may not be a developer: make the change, build it, and tell them in plain words what to try.

## Commands

```sh
make run                       # build, sign, open build/Waldo.app
make install                   # copy it to /Applications
make test                      # unit tests; slow and heavy on the CPU
make test WALDO_EVAL=1         # prompt quality eval; needs the Qwen3.5 4B model
```

Only Command Line Tools are required. Never add a dependency on Xcode.

Run `make run` after a change. Run `make test` only when you touched processing logic, and ask first: it can take a while and heat up the Mac.

## Where things are

| Path | What's there |
|---|---|
| `Waldo/App` | Launch, main window, `AppModel` |
| `Waldo/Popup` | The selection popup and how selections are detected |
| `Waldo/Input` | Hotkeys, clipboard, replacing text, undo |
| `Waldo/Processing` | Prompts (`LlamaPrompts`, `PromptBuilder`), output validation, chunking, diff, glossary |
| `Waldo/Engines` | `InferenceEngine` protocol, llama.cpp and Apple Intelligence engines, `EngineSelector` |
| `Waldo/Models` | Model catalog and downloads |
| `Waldo/Chat` | Chat window, saved history, screen capture |
| `Waldo/Search` | Optional web search |
| `Waldo/Settings` | Settings panes and `SettingsStore` |
| `Waldo/UI/Theme.swift` | Design tokens and shared controls |
| `Config/Info.plist` | App metadata; the version is here |
| `RESEARCH.md` | Why things are built this way; code comments cite its sections |

## Rules that are easy to break

- Our own code can't use `#Preview` or `@Entry`: Command Line Tools don't include the SwiftUI macro plugins.
- Minimum macOS is 13.3. Guard newer APIs with `#available`, and `FoundationModels` with `#if canImport(FoundationModels)`.
- `Vendor/KeyboardShortcuts` is patched; changes are marked with "Waldo patch" comments.
- New views must look right in all three themes (Glass, Mono, Editorial), light and dark. Take colors from `Theme`.
- Keep the promise: text and captures never leave the Mac. Only a web search query may, and only when the user turns search on. No telemetry.
- Prompt examples in `LlamaPrompts` must not repeat cases from `WaldoTests/PromptEval.swift`, which are held out.

## Debugging

```sh
/usr/bin/log stream --level debug --predicate 'subsystem == "com.agustintorres.waldo"'
```

Without an Apple Development certificate the app is signed ad-hoc, so macOS forgets the Accessibility permission after every rebuild. If the popup or hotkeys stop working after a build, run:

```sh
tccutil reset Accessibility com.agustintorres.waldo
```

Then open Waldo and allow it again.
