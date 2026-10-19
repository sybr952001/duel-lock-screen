# Duel Lock Screen

An [Omarchy](https://omarchy.org/) shell plugin that puts a Yu-Gi-Oh-style duel
puzzle in front of your session lock. Win the board, *then* enter your password.

```
┌──────────────────────────────────────────┐
│  Blue-Eyes White Dragon     LP 1200      │
│  ▣ face-up monster                         │
│                                          │
│  hand:  Dark Hole     Mokey Mokey  Mega- │
│         Fissure       Mystical Elf  morph │
│                                          │
│  chain:  ◉  ⚔ 300  ×2      = 600         │
│                                          │
│         password field appears here       │
└──────────────────────────────────────────┘
```

Two phases, both required:

1. **Solve the puzzle.** Link cards into a chain whose running total is the
   opponent's exact LP.
2. **Authenticate.** Only then does the password field appear, and the password
   is checked against PAM.

The order is the whole point. The password alone does nothing, and a solved
puzzle alone does nothing.

## Requirements

- Omarchy with the Quickshell-based shell (developed against 4.0.4)
- `/etc/pam.d/omarchy-lock-password` — shipped by Omarchy. Without it the lock
  refuses to engage rather than falling back to an unlocked session.
- Optional: fingerprint unlock, if `/etc/pam.d/omarchy-lock-fingerprint` exists
  and `fprintd` has an enrolled finger (`omarchy setup security fingerprint`).
  A fingerprint does not skip the duel either.

## Install

```bash
git clone https://github.com/sybr952001/duel-lock-screen \
  ~/.config/omarchy/plugins/makibuu.lock
omarchy plugin enable makibuu.lock
omarchy system lock
```

`omarchy plugin enable` hands the lock over from the built-in `omarchy.lock` to
this plugin. Saving any file under `~/.config/omarchy/plugins/` hot-reloads the
plugin, so edits take effect without restarting the shell; force a rescan with
`omarchy-shell shell rescanPlugins`.

To go back:

```bash
omarchy plugin enable omarchy.lock
rm -rf ~/.config/omarchy/plugins/makibuu.lock
```

> **Keep the plugin id.** `manifest.json` declares `id: makibuu.lock` together
> with `clonedFrom: omarchy.lock`, and that pairing is how the shell routes the
> built-in lock's IPC to this plugin. Renaming the id in a fork leaves the
> running shell talking to a plugin that no longer answers.

## The puzzle

A duel puzzle is a board you have to win inside a single turn. The opponent sits
on an awkward amount of LP with a monster face-up, you get a fixed hand of five
and no deck to draw from, and there is exactly one way through.

Every card in a chain applies one op to the running total:

| Op | Glyph | Effect |
| --- | --- | --- |
| `clear` | ◉ | removes the face-up monster |
| `strike` | ⚔ | adds its value to the total |
| `mult` | × | multiplies the total |
| `halve` | ÷ | floors the total |

Damaging ops are illegal while the monster is up, so the clear has to come first
or the chain never starts. That single rule is what makes the monster
load-bearing without needing a combat simulator.

Then:

- **Exact lethal only.** The chain must total the opponent's LP to the point.
  Short falls and overshoots both lose — an attack declared for lethal against
  an empty board is a loss in the real game too.
- **One solution.** The opponent's LP is *derived from* the generated solution
  rather than picked first, which makes uniqueness structural. The generator
  still re-derives it by walking every chain the hand can form, because a hand
  can reach the same number two different ways and a two-answer puzzle is the
  one failure mode that reads as broken.
- **Three to four links.** Two links is a clear plus one strike, which is not a
  puzzle — the target would be the number printed on a card in your own hand.
- **No repeats.** A hand cannot hold the same op+value pair twice.

Card and opponent names are the real cards from the duel-login set — the
opponents are the monsters it duels against, and the hand's clears are the
game's actual removal. The numbers are still the chain's own, not a card
database: a strike is a monster's printed ATK, but the multipliers are the
lock's mechanic wearing a card's name, because no single real card triples or
septuples a total.

## Layout

| Path | What it is |
| --- | --- |
| `Service.qml` | The plugin entry point. Owns the session lock, PAM contexts, fingerprint retry, stranded-lock recovery, and the `duelSolved` gate that decides whether the session unlocks. |
| `LockView.qml` | The lock screen itself: the two phases, the themed password field, the fingerprint affordance. |
| `duel/DuelModel.js` | The engine. Pure logic, no QML types, `.pragma library`. |
| `duel/DuelBoard.qml` | Board layout, card selection, chain editing, undo. |
| `duel/DuelCard.qml` | One card in hand or in the chain. |
| `duel/ChainTrack.qml` | The committed chain and its running total. |
| `duel/DuelSession.qml` | Puzzle lifecycle: deal, reset, hint. |
| `duel/qmldir` | Declares the components. Siblings resolve implicitly — importing one as `import "DuelCard.qml"` is a *directory* import, which fails to load and takes the whole plugin down. |
| `test/duel-model.test.mjs` | Engine tests. |
| `preview-test.qml` | Standalone harness: drives the engine and audits the layout at several window sizes. |
| `click-test.qml` | Standalone harness: hit-tests the real item tree. |

### Why the Service owns `duelSolved`

`Service.qml` holds the fact that the duel was won and sets it from a
`duelWon` signal, rather than binding to `LockView`'s `duelSolved` property.
The view is declared further down the file, so a binding onto it throws a
`ReferenceError` while the object's bindings are first evaluated — and that
throw escapes from the middle of `beginLock()`, skipping the duel reset that
follows it. The journal caught it on the first real lock.

## Tests

The engine is plain logic with no QML types, so it is testable outside the
shell:

```bash
node --test test/*.test.mjs
```

56 tests. They run against a staged copy of `duel/DuelModel.js` with QML's
`.pragma library` header stripped — everything else is loaded verbatim, so the
tests exercise the same bytes the shell does.

The two QML harnesses import `qs.Commons` and `qs.Ui`, which live in
`$OMARCHY_PATH/shell`. Qt resolves that qualified URI as a *path*, so the import
root needs a `qs` entry — pointing `QML_IMPORT_PATH` at `$OMARCHY_PATH/shell`
directly does not work:

```bash
mkdir -p /tmp/duel-lock-imports
ln -sfn "$OMARCHY_PATH/shell" /tmp/duel-lock-imports/qs

QML_IMPORT_PATH=/tmp/duel-lock-imports \
  quickshell -p ~/.config/omarchy/plugins/makibuu.lock/preview-test.qml
```

Each harness opens its own window, prints its report, and exits. The
`Ignoring unresolvable import .../Commons` lines from the qmlscanner are noise
and can be ignored.

`preview-test.qml` proves the engine works *and* that nothing visible falls
outside the window or overlaps the item above it, at several window sizes — a
lock screen that renders its own hand off the bottom edge still authenticates
correctly, which is exactly why it needs its own check.

`click-test.qml` exists because "nothing was selectable" has three causes that
look identical from the desk and need three different fixes: a card unreachable
behind something that swallows the click, a card whose own `MouseArea` is
disabled, and a click that lands but is refused by the engine in silence. It
hit-tests the real item tree and reports the three apart.

Verified on Omarchy 4.0.4: 56 engine tests pass, the preview audit reports
`0 out of bounds` at all six window sizes, and relock deals a fresh board.

## Credits

Derived from Omarchy's `omarchy.lock` plugin (`Service.qml`, `LockView.qml`),
which is MIT licensed © Basecamp. See [LICENSE](LICENSE). The duel engine, board
and everything under `duel/` are new.
