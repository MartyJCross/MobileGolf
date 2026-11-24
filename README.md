# Mobile Golf

An endless par-3 golf game for Android with realistic ball flight and spin.
Every hole is randomly generated: 70–200 m, a random green, bunkers,
sometimes water, wind and green firmness. One shot per hole, scored by how
close you finish to the pin. Your average is saved on the phone.

## How to play

1. Pick an iron (3-iron to pitching wedge) with `<` / `>`. The number under it is
   how far a full, stock swing carries with no wind.
2. Optional: set trajectory from Low to High. High launches higher with more spin
   (stops faster), low flies under the wind and runs out.
3. Aim by dragging left/right on the course view (or use **Map** for an overhead view).
4. Swing in the bottom area: touch, **pull down** (backswing), then **flick up**
   through where you started.
   * **Flick speed** = club speed. Over 100% is an overswing and gets wild.
   * **Tilt** the flick left/right to change the swing path.
   * **Curve** the flick to open/close the face. The ball curves the way your swipe curves.

Too hard or too easy to reach full power? Change **Settings → Swing sensitivity**.

## The physics (short version)

* **Launch:** D-plane model anchored to TrackMan PGA Tour averages for each iron.
  Face-to-path sets the spin axis (draw/fade), spin loft sets backspin.
* **Flight:** drag + Magnus lift fitted to tour carry and landing angles
  (carry within 2.5%), spin decay, wind that grows with height.
* **Landing:** turf impact model (Penner) where backspin and landing angle decide
  whether the ball releases, checks or spins back; green firmness matters.
* **Roll:** speed-dependent rolling resistance calibrated to Stimp 11; slopes break the ball.

## Development

Godot 4.4.1 (GDScript, Compatibility renderer).

```sh
godot --headless --import                      # once
godot --headless -s tests/run_tests.gd         # run the test suite
godot --headless -s tests/calibrate.gd -- report   # flight vs tour numbers
godot --headless --export-debug "Android" build/MobileGolf.apk
```
