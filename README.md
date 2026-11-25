# Mobile Golf

An endless arcade wedge game for Android with realistic ball flight and spin.
Every hole is a short (30–100 m), randomly generated puzzle: a green that may be
tiered or have a backstop, bunkers, sometimes water, wind, firm or soft greens,
and obstacles you have to work the ball over, under or around: a tree guarding
the line, a tree with high branches, a gap between two trees, a hedge, a stone
wall. One shot per hole, scored by how close you finish to the pin; your
average is saved on the phone.

## How to play

The skill is seeing the shot.

1. **Drag on the course** to move your landing spot (the ring). Use **Map** for a top-down view.
   The arc shows the planned flight, wind included: white is clear, **red hits something**.
   The little side-on view above HIT shows the height, so you can see if you'll clear a tree
   or fit under its branches.
2. **Pick a wedge**: 50°, 55° or 60° (they carry about 100 / 88 / 76 m at full power;
   the game sets the power for your landing spot).
3. **Pick a height**: Punch (low, runs out, goes under branches), Normal, High, Flop
   (very high, lands soft, goes over trees).
4. **Drag the dot on the ball** for spin: down = more backspin (checks, can spin back),
   up = a runner that releases, left/right = draw/fade to curve around things.
5. Think about where it goes **after** it lands (slopes, tiers, firmness, spin), then **HIT**.
   Stop the needle in the green zone for a pure strike (it can be turned off in Settings).

Settings also has a **pro mode**: the preview plans for still air and you read the wind yourself.

## How a hole is made

`HoleGenerator` builds the terrain and green, flies the ordinary shot (55°, normal,
straight) and puts the hole's feature right where that shot goes, then test-plays the
hole with the `ShotPlanner` (every wedge × height × curve) and only keeps it if some
shot lands at the pin without hitting anything.

## The physics (short version)

* **Launch:** D-plane model anchored to TrackMan PGA Tour averages (irons) and typical
  tour wedge numbers. Face-to-path sets the spin axis (draw/fade), spin loft sets backspin.
* **Flight:** drag + Magnus lift fitted to tour carry and landing angles
  (carry within 2.5%), spin decay, wind that grows with height.
* **Landing:** turf impact model (Penner) where backspin and landing angle decide
  whether the ball releases, checks or spins back; green firmness matters.
* **Roll:** speed-dependent rolling resistance calibrated to Stimp 11; slopes break the ball.
* **Obstacles:** trunks and stone walls bounce the ball, canopies and hedges grab it and drop
  it, the flagstick knocks a ball that lands on it down near the hole.

## Development

Godot 4.4.1 (GDScript, Compatibility renderer).

```sh
godot --headless --import                      # once
godot --headless -s tests/run_tests.gd         # run the test suite
godot --headless -s tests/calibrate.gd -- report   # flight vs tour numbers
godot --headless --export-debug "Android" build/MobileGolf.apk
```
