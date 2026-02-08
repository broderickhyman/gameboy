# Game Boy Emulator

A Game Boy emulator written in Zig that simulates the original Nintendo Game Boy hardware from 1989. Currently in active development.

## Status

⚠️ **Work in Progress** - This emulator is still under development. Bugs and crashes are expected. Many games will not run correctly yet.

**Not Implemented:**
- Audio/sound emulation
- Some edge cases in instruction behavior
- Full game compatibility

## Overview

This emulator implements the core components of the Game Boy system:

- **CPU Emulation**: Z80-like Sharp LR35902 processor with cycle-accurate instruction timing
- **Memory & Cartridge Support**: ROM banking (MBC1, MBC3 mappers) for larger games
- **Graphics**: Pixel processing unit (PPU) with SDL2 rendering
- **Test Suite**: 75 built-in test ROMs for validating emulation behavior
- **Game Save Support**: Save/load functionality and RAM persistence

## Quick Start

### Prerequisites
- Zig 0.15.2 or later
- SDL2 and SDL2_ttf libraries (automatically handled by the build system)

### Building
```bash
zig build
```

### Running a Test ROM
```bash
zig build run -- --test 7
```

### Running Your Own Game
```bash
zig build run -- --rom path/to/your/game.gb --display
```

## Features

- Full Z80-like instruction set with cycle timing
- Interrupt handling (V-Blank, Timer, Serial, Joypad)
- Cartridge mapper support (MBC1, MBC3)
- CPU instruction testing with Gameboy-Doctor integration
- Verbose logging and debug modes
- Real-time FPS monitoring

## Keyboard Controls (in graphical mode)

| Key | Action |
|-----|--------|
| **S** | A Button |
| **A** | B Button |
| **Arrow Keys** | D-Pad |
| **Return** | Start |
| **Right Shift** | Select |
| **P / ESC** | Pause/Resume |
| **U** | Save State |
| **L** | Load State |
| **R** | Save RAM |
| **Q** | Quit |

## Project Status

Working:
- CPU instruction tests
- Memory timing
- Graphics rendering for basic games and demos
- Save RAM and cartridge mappers

Still being worked on:
- Wider game compatibility
- Edge cases and bug fixes

## Technologies Used

- **Zig**: Systems programming language for emulation core
- **SDL2**: Cross-platform graphics and event handling
- **zeit**: Rust time library (used for RTC emulation)

## License

See [LICENSE](LICENSE) file for details.

---

For technical documentation, see [CLAUDE.md](CLAUDE.md).
