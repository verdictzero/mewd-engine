# spritegen: Doom-style character sheets out of an image model

A pose template, a prompt and a cutter. You give an image model (Nano
Banana, or any model that edits a picture from reference pictures) one
template sheet, one or more pictures of a character and the sheet's
prompt; it paints the character into every cell; the cutter turns the
result into the game's strip. Troops and non-combatants alike.

```
tools/spritegen/
  pose_sheet.py   makes the templates: out/<profile>/sheetNN-*.png, .json, .prompt.txt, KEY.png
  PROMPT.md       the master prompt; each sheet's .prompt.txt is this plus that sheet's contract
  cut_sheet.py    reads the model's output back off the manifest -> assets/people/<name>.png
  out/mewd/       the game's 4 troop sheets, 5 views          (--profile mewd)
  out/doom/       17 troop sheets, 8 views                    (--profile doom, the default)
  out/mewd-civ/   the 5 sheets a civilian strip needs, 5 views (--profile mewd-civ)
  out/civ/        19 non-combatant sheets, 8 views             (--profile civ)
```

## The sheets

`python3 tools/spritegen/pose_sheet.py --profile civ --list` (any profile)

Troops (`mewd` is 01 to 04 in five views; `doom` is all of these in eight):

| sheet | holds | letters | views |
|---|---|---|---|
| 01 walk | walk cycle, 4 frames, rifle at port arms | A B C D | 8 (or 5) |
| 02 attack | idle; aim, fire, pain | E F G | 8 (or 5) |
| 03 death | 6 dying frames + the corpse | H..N | front only |
| 04 gibs | the body coming apart, 9 frames | O..W | front only |
| 05 run | 4 frames | | 8 |
| 06 crouch | crouch idle, crouch aim, crouch fire | | 8 |
| 07 crouch-walk | 4 frames | | 8 |
| 08 prone | lie, aim, fire | | 8 |
| 09 prone-crawl | 4 frames | | 8 |
| 10 knocked | down-but-not-out crawl, 4 frames | | 8 |
| 11 jump | launch, apex (in the air), land | | 8 |
| 12 melee | rifle butt: wind-up, strike, recover | | 8 |
| 13 reload | 3 frames | | 8 |
| 14 throw | grenade: wind-up, release, follow-through | | 8 |
| 15 use-fall | reach out to use; free fall / skydive | | 8 |
| 16 swim | 4 frames | | 8 |
| 17 victory | 2 emote frames, the rifle held overhead | front only |

Non-combatants (`mewd-civ` is 01 to 05 in five views; `civ` is all of
these in eight). Nothing in the hands, or a prop the row names:

| sheet | holds | letters | views |
|---|---|---|---|
| 01 civ-walk | walk cycle, arms swinging, 4 frames | A B C D | 8 (or 5) |
| 02 civ-flee | panic run, arms up, 4 frames | E F G H | 8 (or 5) |
| 03 civ-stand | stand at ease; cower; hands up | I, J, K | 8 (or 5) |
| 04 civ-death | the troops' death, empty-handed, 7 frames | L..R | front only |
| 05 civ-gibs | the body coming apart, 8 frames | S..Z | front only |
| 06 civ-poses | arms crossed, hands on hips, hands in pockets | | 8 |
| 07 civ-hide | flinch; kneel and cover; kneel, hands behind the head | | 8 |
| 08 civ-sit | on a chair (not drawn), on the ground, cross-legged | | 8 |
| 09 civ-talk | talk, shrug, point | | 8 |
| 10 civ-greet | wave (2), clap (2), cheer | | 8 |
| 11 civ-carry | carrying a box, 4 frames | | 8 |
| 12 civ-phone | on the phone, looking at a phone | | 8 |
| 13 civ-work | sweeping with a broom (2), kneeling at work | | 8 |
| 14 civ-pickup | squatting to the ground; rising with a bag | | 8 |
| 15 civ-limp | wounded walk, 4 frames | | 8 |
| 16 civ-burn | on fire, flailing, 2 frames (no flames: the game draws them) | | 8 |
| 17 civ-dance | 4 frames | | 8 |
| 18 civ-lie | on the back asleep, curled on the side, slumped against a wall (not drawn) | | 8 |
| 19 civ-swim-fall | swim, 4 frames; free fall | | 8 |

Troop sheets 01 to 04 are exactly the game's troop format (`states.gd`
TROOPS: A to G turned, H to W flat; `tools/prep-troops.mjs` describes
the SWAT and ARMY sheets the user drew the same way). The civilian
sheets 01 to 05 are the same shape for a civilian: A to K turned, L to
Z flat (the gibs have eight frames because the letters run out). The
game's own townsfolk are still one drawing each (the shoppers, the
candy girls), so a civilian strip has no state table in the game yet;
the cutter prints the TROOPS-shaped line it would take. The rest of
both sets are for the battle-royale direction.

Every sheet is a grid of equal cells on flat magenta. The grey
mannequin in each cell is the pose and the camera angle: its right arm
and leg are tinted red, its left blue; a dark patch marks the face; a
dark bar is the gun; a brown shape is a civilian's prop (a box, a bag,
a phone, a broom); a yellow star a muzzle flash; a compass in the band
shows the facing from above. The band above each figure carries the
cell's tag (`A1`, `B5`, `H`, `RUN-2/3`). The JSON beside each sheet has
every cell's box as fractions of the picture, so the cutter works at
whatever size the model returns. No mannequin touches its band or its
cell's edges: the generator checks every cell as it draws and reports
any that would.

## The workflow

1. **Make the templates** (already in `out/`; rerun after changing poses):

   ```
   python3 tools/spritegen/pose_sheet.py                       # 17 troop sheets, 8 views -> out/doom
   python3 tools/spritegen/pose_sheet.py --profile mewd        # the game's four, 5 views -> out/mewd
   python3 tools/spritegen/pose_sheet.py --profile civ         # 19 civilian sheets, 8 views -> out/civ
   python3 tools/spritegen/pose_sheet.py --profile mewd-civ    # a civilian strip's five, 5 views -> out/mewd-civ
   ```

   Start with `out/mewd` for a fighter or `out/mewd-civ` for a
   civilian: few sheets, and a strip that drops straight into the
   game's format. The 8-view sheets ask more of the model and only pay
   off for a character whose two sides differ.

2. **One request per sheet.** Attach, in this order: the sheet PNG,
   the character picture(s) (front first; a back view and a side view
   help a lot), `KEY.png`, and, if you have one, a STYLE image: a sheet
   of original Doom sprites (the Zombieman, the marine) for the look
   alone. Paste the sheet's `.prompt.txt` as the message, with your
   character notes filled into the `{{CHARACTER}}` slot (a sentence or
   two: "a woman in a yellow raincoat, black bob, red boots, carries a
   pump shotgun"; for a civilian, say so, and name the props: "the box
   is a grocery box, the phone is a pink flip phone"). Ask for the
   largest output size the model offers (2K or 4K where there is a
   choice): at 1K a cell is only ~130 px wide.

3. **Check the result against the template**: same grid, one figure a
   cell, nothing crossing a line, the back views with no face, the
   profiles facing opposite ways, the muzzle flash only in F, no
   weapon anywhere on a civilian sheet. A bad cell is cheaper to fix
   than a bad sheet: send the output back with the retouch line at the
   end of the prompt.

4. **Name the downloads after their sheet** (the cutter matches on it):
   `myguy.sheet01-walk.png`, `myguy.sheet02-attack.png`, ... or
   `shopkeeper.sheet01-civ-walk.png`, `shopkeeper.sheet03-civ-stand.png`.

5. **Cut**:

   ```
   python3 tools/spritegen/cut_sheet.py MYGUY myguy.sheet0*.png --cells /tmp/myguy
   python3 tools/spritegen/cut_sheet.py SHOPKEEPER shopkeeper.sheet0*.png --height 56 --cells /tmp/shopkeeper
   ```

   writes `assets/people/myguy.png` (51 cells of 64x64: A to G in
   five views, then H to W, the SWAT strip's exact shape; a civilian's
   is 70 cells: A to K in five views, then L to Z), every cell on its
   own in the `--cells` directory, and prints the `States.TROOPS` and
   `Standees._strip` lines to add. A sheet name that exists in both
   the 5-view and the 8-view profile is cut by the 5-view manifest
   unless the picture is the exact size of the other, or `--profile
   doom` (or `civ`) says so; a `civ-` sheet is never cut as a troop's.
   Lying and gib frames wider than the cell are shrunk to fit and
   listed; that is Doom's own economy (the SWAT corpse spans its cell
   too). `--height` sets a standing figure's height in the strip (60,
   the SWAT's); the same factor scales every cell, so corpses and
   crouches keep their size. A civilian's hands-up and fleeing frames
   reach above the head, so a civilian strip wants `--height 56` or
   those cells are shrunk. A JPEG return is fine: the magenta is
   measured, not matched, and the halo is unmixed.

6. **Wire it in**: the two printed lines, an `ACTORS[...]` entry like
   the SWAT's in `states.gd`, and a `_troop(...)` call (a civilian
   needs a table of its own: walk, flee, stand, cower, hands up, death,
   gibs; there is none yet). `tools/fix-sprite-fringe.py` is not needed
   (the cutter already bleeds the edge).

## What to expect, honestly

This works as well as the model follows a template, which today is
good but not perfect, and it has not been run against the image model
itself from here. Things that go wrong, in order of likelihood, and
what to do:

- **A cell is the wrong angle** (a front where a back should be, two
  profiles facing the same way). Retouch that cell (section A of the
  prompt). The red/blue limbs and the compass exist to cut this down.
- **The character drifts** between sheets (a different jacket on sheet
  03 than on sheet 01). Give every request the same character pictures
  AND a good cell from an earlier sheet as an extra reference, and say
  so in the notes.
- **A weapon creeps into a civilian's hands**, or the chair gets drawn
  under the sitter. The civilian block of the prompt says no three
  ways; repeat it in the notes ("she is unarmed; nothing in her hands
  but what the row names"), and retouch the cell.
- **The grid moves** (a cell merged, a row dropped). Regenerate; it is
  usually fine on the second try. Fewer rows per sheet are easier:
  `--views 5` halves the cells on every turned sheet.
- **Soft, painterly, or shadowed output.** The style section of the
  prompt is long for a reason; a STYLE image of real Doom sprites and
  repeating "flat magenta, no shadow, hard pixel edges" in the notes
  both help. The cutter's one-bit alpha then does the rest.
- **Scale drift** (the figure on sheet 02 bigger than on sheet 01).
  The cutter scales by the manifest, not by the drawing, so a model
  that drew bigger makes a bigger sprite. Fix by retouching, or by
  cutting that sheet with its own `--height`.
- **Mirrored views don't match** on 8-view sheets. Use `--views 5` and
  let the game mirror, as the SWAT does; the cost is that a
  right-handed character holds the gun left-handed in views 6, 7, 8,
  which Doom lived with.

The gibs sheets are the ones most models struggle with; the Doom
answer is that the last few frames are a heap and need not match the
template closely.
