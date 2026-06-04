# Transtype

Transtype is a macOS floating writing-translation helper. It watches the current text input through macOS Accessibility APIs and translates text with Apple's on-device Translation framework.

## Features

- Floating, compact translation toolbar.
- Default target language: English.
- Real-time translation for standard macOS text fields and text areas.
- Manual fallback: press `Command+A` yourself to select text, then Transtype reads the selected text and translates it.
- Press the down-arrow button, or the keyboard down arrow when a translation is ready, to replace the original text.
- Uses Apple's macOS Translation capabilities and installed language models.

## Requirements

- macOS with Apple's Translation framework support.
- Accessibility permission for Transtype.
- Installed Apple Translation language packs for the language pairs you want to use.

## Notes

Some apps, including chat apps with custom-rendered input fields, may not expose their text through standard Accessibility text attributes. In those cases, Transtype avoids automatic text selection and relies on user-initiated selection as a fallback.

## Build

Open the project in Xcode, or build from the command line:

```sh
xcodebuild -project opentranstype.xcodeproj -scheme opentranstype -configuration Debug build
```
