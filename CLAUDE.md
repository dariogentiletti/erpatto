# Er Patto: rules for every change

## The look: World of Warcraft classic vanilla (1.12), never modern or retail
Every design decision follows the original vanilla UI, so the addon looks like a window of the game itself.
Check each new frame, popup, list or control against the vanilla character frame before adding it.

Use (the game's own files, drawn through the helpers in UI.lua):
- the window: UI-Character-General art (UI.lua Build); the round portrait shows the vanilla Social window icon
  (FriendsFrameScrollIcon), as the user chose
- never stretch a textured area: rails are a one pixel cut drawn along their length (smooth, as 9-slices in the
  game), areas of stone use the marble inside the character frame art (UI-Character-General, 26..330 x 84..422)
  laid 1:1 in mirrored copies (`MarbleTiles`); FrameGeneral\UI-Background-Marble draws nothing in the user's
  client and the "REPEAT" wrap draws black past a texture's edge: never use either;
  never repeat small noisy pieces (a few pixels repeated show as notches)
- panels: `H.Box` (the slot frame with rivets round dark marble), titles in GameFontNormal, data in the Small fonts
- popups: `H.Chrome` (UI-DialogBox border and background) with `H.DialogHeader` for the title plate
- buttons: `H.Btn` / `H.RedButton`, the red 1.12 button drawn from UI-Panel-Button-Up/Down/Disabled/Highlight;
  never UIPanelButtonTemplate or UIPanelCloseButton (the client draws them as the new dark/round ones); close: `H.CloseX`
- dropdowns: `H.Dropdown` (the 1.12 UIDropDownMenu: CharacterCreate-LabelFrame, text on the right, round arrow) with
  the list in a dialog box (`Sfide.Choose`); never a button that opens a list
- inputs: InputBoxTemplate; checks: UICheckButtonTemplate; radios: UI-RadioButton
- lists: hover `Interface\Buttons\UI-Listbox-Highlight2`, selection `UI-FriendsFrame-HighlightBar-Blue`
- tabs: bottom tabs and `H.TopTab`; no glow on mouseover (the user removed it), only the label turns white
- scroll: only through `H.VanillaScroll` (old arrows, knob, rail); better no scroll at all when the content fits
- announcements (what happens to the patto): one line in the chat with the gold "[Er Patto]" in front and a soft ping;
  the big ones (gogna, tombola, wipe, the crown) also in the game's raid warning letters. Never a window to close
- backgrounds: the dark marble (the user chose it over the lighter header stone)
- feedback: never in the chat; errors and confirmations of a button go in the window it is in (a red line in the
  dialog, the status line of the page), a dialog that is done shows one line and closes by itself
- sounds: a duello a la gogna or a rivincita asked of you plays the battleground horn (PVP_THROUGH_QUEUE)
- explanations: only in the tooltip of the "i" (FriendsFrame\InformationIcon) at the top right of the window,
  one text per tab in Extras.INFO; no guide window

Never:
- textures made by us: only the game's own files (Media holds only the close button, and the karaoke songs the
  user gave, as ogg at seven speeds in Media/karaoke, and the two duel clips the user gave, as frame sheets
  plus ogg in Media/duello, with the "di più" of a rivincita; the Giampaolato's voices in Media/giampy; the
  burattino's music in Media/pupo)
- flat colour fills or tints for highlights (`SetColorTexture` with yellow, gradient bands, gold lines)
- Large/Huge fonts for headings (only the cap number may be GameFontNormalLarge)
- card grids with big empty boxes, modern scroll bars, emblems or logos
- explanatory text: no "passa er mouse", "clicca qui", descriptions of what a page is; put details in tooltips.
  A dialog says what happens and, in one line, what is at stake (e.g. the punishment), never a tutorial
- frame fields that clash with widget internals in the test stub (`w`, `h`, `kind`, `points`): name them otherwise

The Diario page (Progress.lua) is the reference: boxes with a GameFontNormal title and small lines of text.

## Features that must stay apart
- Er duello a la gogna (right click menu): honour only, no piotte. Duel, rivincita, bella; then the winner picks er
  pegno. Its list lives in Progresso, Cimitero ("A la gogna"); its rules in the "i" of Progresso.
- Er Botteghino is everything with piotte: tombola, schedina, sfide (weekly, piotte only, no pegno), taje, gufate,
  bets on duels.

## Text
Addon text in Romanesco; game names (zones, items, professions) in English as the client writes them.
No "·" separators.
