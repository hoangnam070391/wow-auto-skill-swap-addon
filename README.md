# Auto Skill Swap

World of Warcraft addon for **WoW Forever** (1.60.x).

**One key, two skills.** Put a priority skill (A) and a fallback skill (B) on one key. When you press the key, A casts if it can be used; if not (out of range, on cooldown, no mana or rage, target health, no dodge yet...), B casts instead. The action button icon shows the skill that will cast.

- Drag and drop setup, works with your own macros too
- Live icon and button name
- Presets for every class (spell IDs, any client language)
- Per-key conditions: "Always use A / B when" (macro conditions, works in combat)
- Follows action bar pages, stances and forms
- Minimap button (LibDBIcon)

Download: [CurseForge](https://www.curseforge.com/projects/1820334)

## How it works

On WoW Forever one input event tries only one skill that uses the global cooldown, so a plain `/cast A` + `/cast B` macro never falls through to B. A key press is two input events (key down and key up). The addon binds the key to a hidden secure button that tries A on key down and B on key up.

## Commands

- `/skillswap` or `/sswap`: open the settings window
- `/skillswap debug`: print what the addon sees

## License

MIT. Bundled libraries (`libs/`) keep their own licenses.
