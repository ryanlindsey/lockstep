# Shortcuts — the menu bar without an app

macOS Shortcuts can be pinned to the menu bar. That gives phase 1 a real menu
bar UI with no application, no notarisation, no updater, and nothing to
maintain — see [decision 0005](../../docs/decisions/0005-scripts-not-an-app.md).

## Build one

1. Open **Shortcuts**.
2. **File → New Shortcut**.
3. Search the actions list for **Run Shell Script** and add it.
4. Set the script to:
   ```
   $HOME/bin/lockstep 96000
   ```
5. Rename the shortcut — double-click its name in the title bar — to something
   you will recognise in a menu, such as `DAC → 96 kHz`.
6. Open the details inspector (the **ⓘ** button in the toolbar) and tick
   **Pin in Menu Bar**.

That is one rate done. It now appears under the Shortcuts icon in your menu bar
and runs on click.

## Build the rest

Repeat for each rate you actually use. A reasonable starting set:

- `DAC → 44.1 kHz` — most streaming and CD-sourced material
- `DAC → 48 kHz` — video, most system audio
- `DAC → 96 kHz` — common Hi-Res Lossless
- `DAC → 192 kHz` — the top of most Hi-Res catalogues

**Only create Shortcuts for rates your own device reported** in
[phase 0](../../specs/phase-0-probe-your-hardware.md). `lockstep` refuses an
unsupported rate and prints the supported list, so a wrong Shortcut fails safely
— but it is still a Shortcut that never works.

## What this does not do

The Shortcuts appear under the Shortcuts icon in the menu bar, not as their own
icon, so there is no always-visible indicator of the current rate. Shortcuts can
trigger but not display.

Phase 2 removes the need to look: switching becomes automatic, and these
Shortcuts stay as the manual override for when it is wrong or when you are
playing something Music does not know about.
