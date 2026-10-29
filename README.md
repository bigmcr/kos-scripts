# kos-scripts

A collection of scripts for [Kerbal Operating System (kOS)](https://ksp-kos.github.io/KOS/). Scripts include launching, (currently crude) node creation, optimization, automated landing, landing at a target, a very sophisticated node execution script, and several others.

You do not run the scripts one at a time with `RUN`. Instead, a boot file starts a terminal user interface (`loop.ks`), and you type the name of the script you want into it. `loop` runs that script for you, and when it finishes, `loop` releases the controls and is ready for the next command.

## How it works

1. **Boot.** Set the kOS processor's boot file to `boot.ks` (the one in the `boot` folder). When the vessel loads, `boot.ks` opens the terminal, copies the scripts it needs from the archive (`0:`) to the ship's local drive (`1:`), and then starts `loop.ks`. It also keeps track of which scripts it copied, so later changes on the archive can be pulled in with the `update` command.
2. **The interface.** `loop.ks` takes over the terminal. The top of the screen always shows the main status area, and below it is a display that depends on the current mode (orbit, resources, engines, and so on). Anything you type appears at the input line.
3. **Run things.** Type a script name, or one of `loop`'s built-in commands, and press Enter.

### Setting up

1. Copy the contents of this repository into your KSP `Ships/Script` folder (the kOS archive).
2. In the VAB/SPH, give the kOS processor on your vessel the boot file `boot.ks`.
3. Launch. The first boot needs a connection to KSC, because it compiles the scripts on the archive and copies them to the ship. After that, the ship has everything it needs on its own drive.

## Using the terminal

Type a script name (without the file extension) and press Enter. Arguments follow the name, **separated by commas** rather than written as kOS parameters:

```
Exec                  run Exec.ks, which executes the next maneuver node
Circ, Apo             run Circ.ks with the argument "Apo"
Hohmann, target       run Hohmann.ks with the argument "target"
```

Arguments are converted for you: `true`/`T` and `false`/`F` become booleans, numbers become numbers, and anything else stays text. Many scripts take optional parameters. Check the `PARAMETER` lines at the top of each script to see what it accepts.

Some other things to know:

- The up and down arrow keys step through your previous commands. The last 50 are remembered, even after a reboot.
- When a script ends, `loop` unlocks steering and throttle, turns off SAS and RCS, and clears any vector drawings, so the ship is not left under the script's control. A script that wants to keep control can set `dontKillAfterScript`.
- The scripts that `loop` itself needs (`library`, `libraryTransfer`, `loop`, `loopCommands`, `loopTerminal`, and `boot`) are already loaded, so `loop` refuses to run them again from the terminal.
- `exit`, `quit` or `done` leaves `loop` and returns you to the normal kOS terminal.

### Built-in commands

Besides scripts, `loop` has commands of its own that you type the same way. They are defined in `loopCommands.ks`. A few examples:

| Command | What it does |
| --- | --- |
| `mode, <name>` | Change the display shown below the main area. |
| `solar`, `RCS`, `SAS`, `GEAR`, `LIGHTS`, `RADIATORS` | Switch these systems on or off (or toggle them). |
| `hold`, `prograde`, `retrograde`, `normal`, `north`, `up`, ... | Point the ship in a direction and hold it there. |
| `node, ...` | Create a maneuver node. |
| `target, ...` | Set the target. |
| `apoapsis`, `periapsis` | Time warp to just before apoapsis or periapsis. |
| `listFiles` | List the files on the local drive. |

### Display modes

Use `mode, <name>` to choose what is shown below the main area:

| Mode | Names that select it |
| --- | --- |
| Orbit | `Orbit`, `OrbitNext`, `OrbitTarget`, `OrbitTargetNext`, `OrbitNode` |
| Resources | `Resources` |
| Body | `Body` |
| Processors | `Processors`, `kOS`, `CPU` |
| Ship | `Ship`, `deltaV` |
| Ship info | `ShipInfo`, `Stage`, `Thrust`, `TWR` |
| RCS | `RCS`, `Thrusters` |
| Engines | `Engines` |
| Scripts | `Scripts`, `Files`, `Library` (add a page number, such as `Scripts 2`) |
| Universe | `Universe`, `World`, `settings` |
| Help | `info`, `help` |

`mode, Default` goes back to the default display.

## Keeping scripts up to date

The ship runs its own local copies of the scripts, so editing a file on the archive does not change a ship that has already booted. Three commands manage this:

- `build` compiles the changed scripts on the archive into `0:Compiled`. Run it from a ship that is not doing anything important, since compiling pauses the program.
- `update` copies changed and new scripts from that build to the ship (`update, T` copies everything again). A script that was already loaded needs a `reboot` before the new version is used.
- `reinstall` deletes the ship's local scripts and installs them all again from the archive on the next boot.

`reboot` restarts the kOS processor, which runs `boot.ks` again.
