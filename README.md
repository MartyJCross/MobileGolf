# Mobile Golf

An endless par-3 golf game for Android with realistic ball flight and spin.
Every hole is randomly generated: 70–200 m, a random green, bunkers,
sometimes water, wind and green firmness. One shot per hole, scored by how
close you finish to the pin. Your average is saved on the phone.

## How to play

1. Pick an iron (3-iron to pitching wedge) with `<` / `>`. The number under it is
   how far a full, perfectly timed swing carries with no wind.
2. Optional set-up:
   * **Trajectory** Low ↔ High: low flies under the wind and runs out, high spins and stops.
   * **Shape** Draw ↔ Fade: sets your stance and swing path. Timing decides whether it comes off.
3. Aim by dragging left/right on the course view (or use **Map** for an overhead view).
4. Swing with the golfer at the bottom of the screen:
   * **Hold** to swing back. Hold longer = longer backswing = more distance
     (watch the meter; the white mark is a full swing, past it is an over-swing).
   * **Let go** to start down. Your arms pull the club down with the wrists cocked: that's the lag.
   * **Tap** to release the club. The wrists unhinge and the club whips through.
     * On time: full speed, square face.
     * Early (casting): the club flips past your hands: higher, weaker, face closing, pulls and hooks.
     * Late: the club is still lagging: lower, face open, pushes and slices.
     * No tap: your wrists give way late on their own: a weak, low push-slice.

The downswing plays in slow motion so it can be timed by a human thumb.
**Settings → Downswing speed** goes from 30% up to real speed.

## The swing model

The swing is a double pendulum (arms + club hinged at the wrists), the classic
golf-research model. The body drives the arms with a torque; the wrists hold the
club cocked until you tap, then fire it through. Clubhead speed, how far the club
lags or flips at impact, and how centred the strike is all come out of the physics,
and are turned into club speed, face angle, path, dynamic loft and strike for the
ball-flight model. A perfectly timed full swing is ~90 mph with the club in line
with the arms at impact.

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
