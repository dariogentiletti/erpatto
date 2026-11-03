# Er Patto: rules for every change

## The look: World of Warcraft classic vanilla (1.12), never modern or retail
Every design decision follows the original vanilla UI, so the addon looks like a window of the game itself.
Check each new frame, popup, list or control against the vanilla character frame before adding it.

Use (the game's own files, drawn through the helpers in UI.lua):
- the window: UI-Character-General art (UI.lua Build); the round portrait shows the vanilla Social window icon
  (FriendsFrameScrollIcon), as the user chose
- textures are never stretched: `Tile` repeats them at their own size (mirrored copies, no seams)
- panels: `H.Box` (the slot frame with rivets round dark marble), titles in GameFontNormal, data in the Small fonts
- popups: `H.Chrome` (UI-DialogBox border and background) with `H.DialogHeader` for the title plate
- buttons: UIPanelButtonTemplate; inputs: InputBoxTemplate; checks: UICheckButtonTemplate; radios: UI-RadioButton
- lists: hover `Interface\Buttons\UI-Listbox-Highlight2`, selection `UI-FriendsFrame-HighlightBar-Blue`
- tabs: bottom tabs and `H.TopTab`, with UI-Character-Tab-RealHighlight
- scroll: only through `H.VanillaScroll` (old arrows, knob, rail); better no scroll at all when the content fits
- announcements: plain big Friz Quadrata text with a shadow (like the zone text), nothing behind it

Never:
- flat colour fills or tints for highlights (`SetColorTexture` with yellow, gradient bands, gold lines)
- Large/Huge fonts for headings (only the cap number may be GameFontNormalLarge)
- card grids with big empty boxes, modern scroll bars, emblems or logos
- explanatory text: no "passa er mouse", "clicca qui", descriptions of what a page is; put details in tooltips

The Diario page (Progress.lua) is the reference: boxes with a GameFontNormal title and small lines of text.

## Text
Addon text in Romanesco; game names (zones, items, professions) in English as the client writes them.
No "·" separators.
