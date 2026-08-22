**English** | [Русский](README.ru.md)

# Virtual Console

An 8-bit virtual computer built from scratch in C++: its own CPU, its
own assembler, a small C-like language that compiles down to that
assembler, and a resident terminal "OS" you can type commands into -
complete with color text mode, bitmap graphics with sprites/tiles, a
simple 3D accelerator, tracker music playback, and a two-panel file
manager. No existing CPU architecture is emulated - the instruction
set, the memory map, and every device on the bus are original to this
project.

## What's inside

- **A custom 8-bit CPU** - its own instruction set, interpreted in
  [`CPU.cpp`](VirtualConsole/CPU.cpp).
- **A custom assembler** ([`Assembler.cpp`](VirtualConsole/Assembler.cpp))
  - labels, relocation, the works.
- **Mini-C** - a deliberately small C-like language that compiles
  straight into the same assembly ([`Compiler.cpp`](VirtualConsole/Compiler.cpp)).
- **A resident "operating system"** ([`SHELL.ASM`](VirtualConsole/C/SHELL.ASM))
  - an interactive terminal with DOS-style commands (`cd`, `dir`,
    `type`, `copy`, `build`, `exec`, ...) and nested program
    execution (a running program can launch another one and get
    control back when it exits).
- **Two virtual disks** that are just plain folders on your machine
  (`C/`, `D/`).
- **Text mode** - 80x25, 16 colors, CP866/box-drawing characters -
  plus a separate **320x240 bitmap mode** with sprites and tiles
  ([`VideoCard.cpp`](VirtualConsole/VideoCard.cpp)).
- **A small 3D accelerator** - vertices/triangles
  ([`Gpu3D.cpp`](VirtualConsole/Gpu3D.cpp)).
- **Sound** - a ProTracker `.mod` player
  ([`ModLoader.cpp`](VirtualConsole/ModLoader.cpp) /
  [`SoundCard.cpp`](VirtualConsole/SoundCard.cpp)).
- **Ready-made programs**: a Snake game, a spinning 3D cube demo, a
  tile-scrolling demo, a music player, and a two-panel Norton
  Commander-style file manager ([`FM.MC`](VirtualConsole/C/TOOLS/FM.MC))
  that can launch other programs with Enter.

## Quick start

**Requirements**: Windows (the host uses `<windows.h>`, `_getch()`,
and console APIs directly - see [`main.cpp`](VirtualConsole/main.cpp)),
Visual Studio with the "Desktop development with C++" workload.

**Build**: open [`VirtualConsole.slnx`](VirtualConsole.slnx) in Visual
Studio and build the `x64` configuration (the same thing
[`.vscode/tasks.json`](.vscode/tasks.json) does via MSBuild, if you'd
rather build from the command line/VS Code).

**Run**: launch `VirtualConsole.exe` **from inside the `VirtualConsole/`
folder** - `boot.asm` and the `C/`/`D/` disk folders need to be right
next to it.

Once the terminal boots, try:

    dir
    cd demos
    build snake.mc
    snake

...or just type `fm` to open the file manager.

## Repository layout

- `VirtualConsole/*.cpp`/`*.h` - the host emulator: CPU, bus, every
  device, the assembler, the Mini-C compiler.
- `VirtualConsole/boot.asm` - the minimal bootloader.
- `VirtualConsole/C/` - "disk C": `SHELL.ASM`, plus `DEMOS/`, `GAMES/`,
  `TOOLS/`, and `DEV/SRC/` (source for the demos/tools).
- `VirtualConsole/D/` - "disk D": an empty scratch disk.
- [`VirtualConsole/ASSEMBLY.md`](VirtualConsole/ASSEMBLY.md) - the
  full technical reference.

## Documentation

[`ASSEMBLY.md`](VirtualConsole/ASSEMBLY.md) is the complete technical
reference: the instruction set, every memory-mapped device with its
address range, the interrupt model, and the full Mini-C language guide
(with a quick-reference cheat sheet at the end).

## Third-party code and assets

- [`stb_image.h`](VirtualConsole/stb_image.h) by Sean Barrett (public
  domain / MIT, see the file header) - used to load PNG sprites and
  tiles.
- `C/DEMOS/SPRITES.png` / `C/DEMOS/TILES.png` - from the
  [**32rogues**](https://sethbb.itch.io/32rogues) asset pack by Seth
  (name-your-own-price; commercial and non-commercial use and
  modification allowed, reselling/redistributing the pack itself is
  not, no generative-AI/NFT use; credit appreciated but not required).
- `C/DEMOS/space_debris.mod` - "Space Debris", composed by
  Markus "Captain" Kaarlonen in 1991, first place at Anarchy Easter
  Party 1991 (Sweden). No formal license is published for this
  module; see the [composer's own page](https://markuskaarlonen.com/space-debris)
  or [The Mod Archive](https://modarchive.org/module.php?57925=).
