# ElvUI MerathilisUI HoverCast Tooltip

A small companion addon for [MerathilisUI](https://www.curseforge.com/wow/addons/merathilis-ui) (an ElvUI edit). While you hover a unit frame, it shows a tooltip listing the HoverCast click-casting bindings that apply to that unit, for the modifier keys you are holding.

## Features

- Lists the bindings for the **modifiers currently held**. Holding Alt shows the Alt+button bindings, holding nothing shows the plain ones. It updates as you press and release Shift, Ctrl, Alt or Meta.
- Filters by **target type**. Bindings set to Enemy do not show on friendly units, and Friendly bindings do not show on enemies. Dispel, external and rez presets are friendly-only.
- Hides **out-of-combat-only** bindings while you are in combat, and bindings that are off in your current content context (solo, party, raid, PvP).
- Skips spells your character does not know, and lets a spec binding replace a global one on the same key.
- Option to show only on **party and raid frames**.
- Placement: above, below, left, right, or **Auto** (first side with room on screen), anchored either to the hovered frame or to the **whole party/raid frame**, so it does not cover the other frames.
- Gap between the tooltip and its anchor.

Settings are in the ElvUI config under "MerathilisUI HoverCast Tooltip", or open them with `/hctip`.

## Requirements

- ElvUI
- MerathilisUI, with HoverCast enabled. The tooltip shows nothing while HoverCast is off, and HoverCast stays off while Clique is loaded.
- Retail (Interface 120105)

## Installation

Copy the `ElvUI_MerathilisUI_HoverTooltip` folder into `World of Warcraft/_retail_/Interface/AddOns/`.

## How it works

The addon changes nothing in MerathilisUI. It reads from it:

- **Bindings:** `HC:GetSpecBindings()` and `HC:GetGlobalBindings()`, where `HC = MER:GetModule("MER_HoverCast")`, return the saved bindings. The addon filters them for modifiers, target type, combat state and content context.
- **Display:** `GetBindingName`, `GetBindingIcon` and `FormatKey` give the name, icon and key text.
- **Which frames count:** MerathilisUI wraps the global `ClickCastFrames`. Looking a frame up in it tells whether HoverCast has registered that frame.
- **Hover detection:** MerathilisUI does not expose a "frame entered" callback. The addon checks the frame under the mouse every 0.05 seconds and redraws only when the frame, unit, modifiers, combat state or settings change.
- **Party/raid detection:** by frame name (`ElvUF_Party*`, `ElvUF_Raid*`, `CompactParty*`, `CompactRaid*`). The whole-group anchor uses the highest matching ancestor frame.
- **Auto direction:** after the tooltip is sized, it picks the first side with room on screen. A single frame tries above, below, right, then left. A whole group tries right, left, below, then above.
- **Look:** the tooltip is a separate `GameTooltip` frame styled through ElvUI's tooltip module. It follows ElvUI's tooltip style, not necessarily every skin tweak that targets the main `GameTooltip`.

## Known limitations

- It depends on MerathilisUI's public HoverCast methods and saved-data layout. If an update renames or reshapes them, the tooltip may break until this addon is updated.
- Precedence between bindings (spec over global, spell known or not) is reimplemented here and may differ from MerathilisUI in unusual cases. A binding MerathilisUI later merges into one macro is shown from the raw saved entries.
- The whole-group anchor needs the group frame to report a real size. If it does not, the tooltip falls back to the hovered frame.

## Development note

This addon was built with AI assistance (GitHub Copilot). The author set the requirements, directed the design and tested it in game.

## License

[MIT](LICENSE). MerathilisUI is also MIT licensed (Copyright (c) 2026 Merathilis). This addon contains no MerathilisUI code, only calls to its public API. It is not affiliated with or endorsed by Merathilis or the ElvUI team.
