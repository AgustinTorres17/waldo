# Waldo

Correct, translate and rephrase what you write, in any app on your Mac. Waldo runs on your computer: no account, no servers, no subscription.

**[Website](https://agustintorres17.github.io/waldo-landing/)**

- **Correct and translate** selected text in 9 languages, and review every change before replacing it.
- **Rephrase** to say the same thing better.
- **Modes** for how you want to sound, with a mode and language per app.
- **Glossary** for the words that must stay as they are.
- **Chat** with Waldo about selected text or anything on screen, with optional web search.
- **Hotkeys** for everything, and undo for the last replacement.

## Install

You need a Mac with Apple silicon, macOS 13.3 or later, at least 8 GB of memory, and about 4 GB of free disk space. Waldo has been tested on macOS 26; earlier versions should work but haven't been tried.

**1. Install Apple's Command Line Tools**, if you don't have them. A window opens: click Install.

```sh
xcode-select --install
```

**2. Download and build Waldo.** The first build takes a few minutes.

```sh
git clone https://github.com/AgustinTorres17/waldo.git
cd waldo
make install
open /Applications/Waldo.app
```

**3. Allow Accessibility.** Waldo asks for it when it opens: turn it on in System Settings › Privacy & Security › Accessibility. Waldo needs it to read your selection and replace the text.

**4. Download a model.** Go to Settings › Engine and pick one:

| Model | Download | Best for |
|---|---|---|
| Qwen3.5 4B | 2.7 GB | Macs with 16 GB of memory or more |
| Qwen3.5 2B | 1.4 GB | Macs with 8 GB of memory |

Reading screenshots needs one extra download, and macOS asks for Screen Recording permission the first time you capture the screen. On macOS 26 with Apple Intelligence, Waldo can also use Apple's on-device model.

### Update

```sh
cd waldo
git pull
make install
tccutil reset Accessibility com.agustintorres.waldo
open /Applications/Waldo.app
```

Allow Accessibility again when Waldo asks. macOS forgets the permission after each build, unless you have an Apple Development certificate in your keychain.

## Use it

Select text in any app and the popup appears. Or use a hotkey:

| Action | Hotkey |
|---|---|
| Correct or translate the whole field | ⌥⌘T |
| Correct or translate the selection | ⌥⇧⌘T |
| Rephrase the whole field | ⌥⌘R |
| Rephrase the selection | ⌥⇧⌘R |
| Undo the last replacement | ⌥⌘Z |
| New chat | ⌥⌘K |
| Capture a region and ask | ⌥⌘E |
| Capture the whole screen and ask | ⌥⇧⌘E |

You can change them in Settings › Hotkeys.

In Chromium browsers such as Chrome and Brave, the popup needs to be turned on per browser in Settings › Popup. Hotkeys work without it.

## Make it yours

Waldo is meant to be changed, and you don't need to know Swift. Open this folder with the coding agent you prefer and describe what you want:

> Add a Summarize button to the popup.

> Add Dutch to the languages.

> Give Waldo a fourth theme in my company's colors.

The agent finds its instructions in [`AGENTS.md`](AGENTS.md). When it's done, `make run` opens your version.

## Privacy

Your text, captures and chats stay on your Mac. Waldo has no telemetry. It only connects to the internet to:

- Download models from Hugging Face, when you ask it to.
- Send a search query to DuckDuckGo, or to your own SearXNG server, when you turn on web search in a chat. Your captures are never sent.

## License

[GPL-3.0](LICENSE). See also the [third-party notices](THIRD_PARTY_NOTICES.md).
