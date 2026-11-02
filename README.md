# Er Patto

Addon pe' WoW Forever: er patto de livellamento de 'n gruppo d'amici. Cap settimanali pe' squadra, livelli de tutti, quest, dungeon, duelli, BG, titoli.

## Struttura

La cartella der repo è la cartella dell'addon: `ErPatto.toc` sta in cima.

| File | Che fa |
|---|---|
| `Util.lua` | Funzioni comuni: ora del server, formati, serializzatore |
| `Model.lua` | Calcolo dei cap settimanali dalle ore a settimana |
| `Patto.lua` | Stato del patto, membri, regole, pulizia dei dati in arrivo |
| `Comms.lua` | Sincronizzazione tra i membri (canale, sussurri, gossip) |
| `Tracker.lua` | Quello che il personaggio fa: livelli, quest, sordi, dungeon, PvP |
| `Journal.lua` | Diario grezzo salvato in locale, pe' funzioni future |
| `UI.lua`, `Character.lua`, `Progress.lua`, `Titles.lua` | Finestra, schede e titoli |
| `Diag.lua` | `/patto diag`: prova de comunicazioni e texture |
| `Media/` | La pietra de sfondo e la X, fatte da `tools/gen_media.py` |
| `tests/` | Test in Python + Lua 5.1 (`pip install lupa`), co' le API de WoW finte |

## Prova in locale

Copia (o linka) la cartella in `World of Warcraft/_retail_/Interface/AddOns/ErPatto`. Quando aggiungi file novi (texture), riavvia er gioco: `/reload` nun basta.

Test:

```
pip install lupa
cd tests
python3 test_ui.py
```

I test girano da soli a ogni push (GitHub Actions, "Tests").

## Pubblicà 'na versione su CurseForge

1. Fai er commit su `main`.
2. Metti 'n tag co' la versione e mandalo:

```
git tag -a v0.9.6 -m "v0.9.6"
git push origin v0.9.6
```

GitHub Actions ("Release") prepara lo zip co' [BigWigsMods/packager](https://github.com/BigWigsMods/packager) e lo carica su CurseForge. La versione nel `.toc` (`@project-version@`) diventa er nome der tag.

Ner repo servono:
- `## X-Curse-Project-ID` nel `.toc`, cor numero der progetto CurseForge;
- er secret `CF_API_KEY` (Settings → Secrets and variables → Actions), co' 'n token preso da https://legacy.curseforge.com/account/api-tokens;
- Settings → Actions → General → Workflow permissions: "Read and write".
