# Pole Tidy

A Factorio 2.0 mod that removes electric poles other poles make redundant. As your poles gain quality they cover
more, and the old dense grid is left behind; Pole Tidy finds the poles you no longer need.

- **Pole tidy tool** (shortcut bar): drag over poles. The redundant ones are marked for deconstruction and your
  robots take them away. Shift-drag only shows which ones would go.
- **Auto mode** (the lit button next to the tool): when a pole is upgraded, poles it makes redundant are removed. The pole that was just built, and line ends that power nothing yet (a line someone is still running, e.g. AI Crew), are left alone.
- With **GUI Unifyer**, the button in the top-left mod bar takes its button style (lit while on), like the buttons it knows.

A pole is only removed if every building it powers stays powered and no electric network gets split.
Safe to add or remove at any time.

## Install

Copy this folder into your mods folder (`%APPDATA%\Factorio\mods`) as `pole-tidy`, or clone it there:

```
git clone https://github.com/watdafawx/pole-tidy
```

`test\run.py` runs the headless tests (set `FACTORIO_EXE` if the game isn't in a usual Steam library).

## License

MIT, see [LICENSE](LICENSE).
