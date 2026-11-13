# Zero for the Omarchy bar

An Omarchy shell bar widget for [Zero](https://github.com/chayotesudado/zero),
a Todoist app for Omarchy. The bar shows Zero's pixel check in your
theme's color; click it for what's due today and overdue, tick tasks off, and
add to your Inbox without opening anything.

Zero is an unofficial client, not affiliated with or endorsed by Doist, the
makers of Todoist. Todoist and its logo are Doist's trademarks.

## Install

1. Install the Zero app and sign in to Todoist there; the widget talks to
   Todoist only through the `zero` command, so it never sees your API token.
2. Add the widget:

   ```sh
   omarchy plugin add https://github.com/chayotesudado/omarchy-zero.git --enable
   ```

## Use

| Key / action | Does |
| --- | --- |
| Click the icon | Open the list |
| Middle-click | Open Zero |
| J / K, ↓ / ↑ | Move through tasks |
| Space or Enter | Complete the task under the cursor |
| Click a circle | Complete that task |
| A | Jump to the add box (adds to the Inbox; `#Project` and dates work) |
| O | Open Zero |
| R | Refresh |
| Esc | Close |

Priority circles use the theme's red, orange, and blue; everything else uses
the shell's colors, so it follows theme switches.

Settings (Omarchy's bar settings): how often to refresh, in minutes.

IPC: `omarchy-shell chayotesudado.zero status | refresh | toggle | add "<text>"`
(handy for a Hyprland binding).

## Development

Link a checkout instead of installing it, then restart the shell after edits:

```sh
ln -sfn "$PWD" ~/.config/omarchy/plugins/chayotesudado.zero
omarchy restart shell
node --test tests/
```
