# The 2D game's rock textures and the hanging island

**Read this before touching the 2D board's art.** Pointer lives in `CLAUDE.md`.

All art lives in `assets/`, downscaled from the originals (the source art was 2048²/2752px, ~24MB total — far too heavy for a phone; it's 3.6MB now):

- `space_far.png` — starfield background
- `rock_floor.png` — tiled across walkable floor tiles AND wall tops
- `rock_wall.png` — tiled across the vertical wall faces
- `island_underside.png` — the hanging underside (transparent PNG)

Three things that are easy to get wrong here:

1. **UVs come from WORLD position, not from the tile.** That's what makes the rock flow continuously across neighbouring tiles instead of restarting on each one. `_world_uvs()` does this; `texture_repeat` is enabled on the Board in `_ready()`.
2. **Wall faces need a much bigger texture scale than the floor** (`WALL_TEX_WORLD` 900 vs `FLOOR_TEX_WORLD` 384). The isometric angle squashes a wall face to roughly a third of its width on screen, so at floor scale the rock detail compresses into what looks like a picket fence.
3. **The underside art is mostly empty space — use `UNDERSIDE_SRC`, not the whole image.** The top 14.2% of `island_underside.png` is fully transparent and the rock spans only 83% of its width. Drawing the whole image anchors that PADDING to the board edge instead of the rock, which is why the island looked detached through three separate attempts to "nudge it closer". `UNDERSIDE_SRC` holds the measured opaque bounds. If the art is ever replaced, re-measure them.
4. **The island underside is SPLIT IN TWO and sheared onto the board's V.** The board's belly runs left corner → lowest corner → right corner, so a single straight-topped image hung along one arm leaves the other half of the platform with nothing under it — the rock then reads as a separate object floating below (this took three attempts to get right). `_draw_underside()` splits the art down the middle and shears each half onto its own arm. The art tapers to a point at its centre, so both halves meet at the board's lowest corner and the island's deepest point lands under the platform's deepest point. It's drawn FIRST so the board's own rock sides cover the join.

The rock is deliberately dark — the `TINT_*` constants multiply the mid-grey source art down so neon stays the brightest thing on screen. Raise them to lighten the rock. Pits stay flat black (no texture) so they still read as holes.

