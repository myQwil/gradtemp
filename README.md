# gradtemp
A hyprsunset waybar module

Works with hyprsunset's IPC feature via hyprctl to perform gradual transitions between color temperatures.

## How to build
Open this folder in a terminal and run the following command:
```bash
zig build --release=fast
```

## How to use
The executable is meant to be called periodically with a systemd timer or a custom waybar module.

### systemd timer
Move the files in the `systemd` folder to `~/.config/systemd/user` and change the `ExecStart` path in `gradtemp.service` to match the location of the executable.

Enable and start the timer with:
```bash
systemctl --user enable gradtemp.timer
systemctl --user start gradtemp.timer
```

### waybar module
Paste the snippets in the `waybar` folder into the files with the same name at `~/.config/waybar` and change the `exec` and `on-click` fields to match the location of the executable. Then add `"custom/colortemp",` to one of the module lists.

To see the module, restart waybar with:
```bash
killall waybar; waybar & disown
```
The module can be toggled on and off by clicking on it.

## Args
The executable accepts the following arguments:
- `<integer>`: Prints out the temperatures over a 24-hour period, with the integer specifying the number of segments to divide each hour into.
- `<non-integer>`: Toggles the enabled/disabled state, which is stored in `~/.cache/gradtemp/state`.

## Config options
gradtemp will look for a json config file at `~/.config/gradtemp/config.json`

Options include:
- `"day": int` - The color temperature for day time.
- `"night": int` - The color temperature for night time.
- `"dawn": {object}` - The time interval where night turns to day.
- `"dusk": {object}` - The time interval where day turns to night.

`"dawn"` and `"dusk"` are json objects with the following fields:
- "`"start": float`" - The hour that the interval starts.
- "`"end": float`" - The hour that the interval ends.
- `"scale": "enum"` - Which scaling method to use. Possible values include:
  - `"linear"` - Linear scaling.
  - `"grow"` - Growing exponential scaling (day turns to night faster).
  - `"decay"` - Decaying exponential scaling (night turns to day faster).

Time intervals use the hours of a 24-hour clock. For example, `[4, 6]` means the interval occurs between 4am and 6am, while `[16, 18]` would occur between 4pm and 6pm.

Intervals can also cross through midnight. For example, `[22, 2]` (10pm to 2am) is a valid time interval.

To make a transition occur instantly, simply give the time interval's start and end times the exact same value.
