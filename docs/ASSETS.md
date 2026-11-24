# Zero-License Asset Shortlist

Sources checked on 2026-11-23, straight from the roadmap toolchain table
(OpenGameArt, Freesound, Lospec, jsfxr/ChipTone). Everything listed here is
CC0 / public domain: no attribution, no fees, safe for commercial use.
Each entry was verified on its asset page, not just on a search hit.

## Music - OpenGameArt

| Pack | Author | License | Why it fits |
| --- | --- | --- | --- |
| Dark Sci-Fi Audio Pack | SRG774 | CC0 1.0 | 5 cold, tense ambient tracks + 3 UI stings; reads as the office-at-night mood |

Link: https://opengameart.org/content/dark-sci-fi-audio-pack

## Sound effects - Freesound + generators

| Asset | Author | License | Notes |
| --- | --- | --- | --- |
| Typewriter: keys, carriage, bell | Gate13, sound 697389 | CC0 | Contains short spoken segments between takes - trim before use |

Link: https://freesound.org/people/Gate13/sounds/697389/

Generators (zero license by construction - you own the output):

- ChipTone (SFB Games): every sound you generate is CC0.
  https://sfbgames.itch.io/chiptone
- jsfxr (sfxr.me): repo is Unlicense, public domain.
  https://github.com/grumdrig/jsfxr

For more recorded sounds, filter Freesound by CC0 and always re-check the
badge on the sound page itself:
https://freesound.org/search/?q=YOUR+TERM&f=license:%22Creative+Commons+0%22

Search terms that match the office loop: typewriter, footsteps concrete,
door creak, paper rustle, wall clock, cigarette lighter, camera shutter,
city hum.

## Palettes - Lospec (free to download and use)

| Palette | Author | Colors | Mood |
| --- | --- | --- | --- |
| Chroma Noir | VEXED | 22 | grey ramp + rust + one cold blue; noir base |
| Gotham-30 | 1bitComrade | 30 | gothic comic ramp, strong for night exteriors |
| Godscrown | Caaz | 21 | harsh-light noir, good for alarm frames |

Export any of them as .gpl and drop the file beside
assets/palettes/redharbor_noir.gpl.

- https://lospec.com/palette-list/chroma-noir
- https://lospec.com/palette-list/tag/noir

## Textures - OpenGameArt (optional)

The texture pipeline is procedural (assets_src/gen_textures.py), so packs
serve as reference or grime-overlay material only.

| Pack | Author | License | Notes |
| --- | --- | --- | --- |
| Tiny Texture Pack series | Screaming Brain Studios | CC0 | 512/256/128, built for PS1-style low-poly; brick, concrete and more |

Link: https://opengameart.org/content/tiny-texture-pack-brick-10-128x128png

## Checked and rejected (not zero license)

- Dark Ambient Loop 13 (MundoSound) - CC-BY 3.0: attribution required.
- Most plain Freesound search hits default to CC-BY or CC-BY-NC: always
  use the CC0 filter URL above and re-check the badge on the sound page.

## Integration map

- audio/ is empty today: the music loop lands here first, then SFX as
  wav or ogg.
- assets/palettes/ takes Lospec .gpl exports.
- gen_textures.py stays procedural; CC0 texture packs are fallback only.
