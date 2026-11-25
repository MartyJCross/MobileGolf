# Mobile Golf

An endless arcade wedge game for Android with realistic ball flight and spin.
Every hole is a short (30–100 m), randomly generated puzzle: a green that may be
tiered or have a backstop, bunkers, sometimes water, wind, firm or soft greens,
and obstacles you have to work the ball over, under or around: a tree guarding
the line, a tree with high branches, a gap between two trees, a hedge, a stone
wall. One shot per hole, scored by how close you finish to the pin; your
average is saved on the phone.

## How to play

1. **Aim:** drag left/right on the course. The ring shows where a full swing lands
   (still air); **Map** gives a top-down view.
2. **Pick a wedge** (50°, 55°, 60°: about 100 / 88 / 76 m full), a **height**
   (Punch runs low under branches, Flop goes high over trees) and **backspin** on the
   little ball (down = more spin, up = a runner).
3. **Swing** in the lower half of the screen: put your thumb down, **pull down** to swing
   back (how far you pull = power; the ring slides to where that power lands), then
   **swipe up through the ball**. Swipe speed doesn't matter.
4. **Shape it with your thumb:** straight back and straight through goes straight.
   Swipe through to the right of your backswing line to open the face (fade), to the
   left to close it (draw). Pull back at an angle and come through on the same line to
   push or pull it without curve.
5. Think about wind, slopes, firmness and spin: where it goes after it lands is the game.

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
