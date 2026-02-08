# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is a Game Boy emulator written in Zig. It implements CPU emulation, memory management (including cartridge mappers), PPU (display) rendering via SDL2, and timer/interrupt functionality. The emulator can run both test ROMs (via a JSON test suite) and custom game ROMs with full SDL2 graphical display.

## Build & Run Commands

### Basic Commands
```bash
# Build the project
zig build

# Run the emulator with a test ROM (e.g., test #7)
zig build run -- --test 7

# Run the emulator with a custom ROM
zig build run -- --rom path/to/game.gb
```

### Common Flags
- `--test <id>`: Run a test from the test suite (ID 0-74)
- `--rom <path>`: Load a custom ROM file
- `--display`: Show SDL2 window (auto-enabled for certain test types)
- `--verbose`: Enable verbose CPU logging
- `--debug`: Enable debug output
- `--log`: Write execution log to `output/output.log`
- `--mem`: Output memory state
- `--fast`: Run at 2x speed in display mode

### Example Development Commands
```bash
# Run test #7 with verbose output
zig build run -- --test 7 --verbose

# Run a ROM with logging enabled
zig build run -- --rom tetris.gb --display --log
```

## Architecture & Key Components

### Module Structure
- **`src/main.zig`**: Entry point; handles CLI parsing, test suite loading, and main run loop (display or gameboy-doctor mode)
- **`src/cpu/Cpu.zig`**: CPU execution engine; cycle tracking and instruction dispatch
- **`src/cpu/Timer.zig`**: Timer/interrupt logic
- **`src/memory/Memory.zig`**: Memory management; handles ROM banking, RAM banks, VRAM, WRAM, OAM, I/O, and HRAM
- **`src/memory/RomBank.zig`**: ROM bank representation (16 KB chunks)
- **`src/memory/Ram.zig`**: Generic RAM region (VRAM, WRAM, OAM, etc.)
- **`src/display/PPU.zig`**: Pixel processing unit; renders Game Boy graphics via SDL2
- **`src/io/Joypad.zig`**: Button input handling
- **`src/utils.zig`**: Utility functions for bit operations, file paths, mappers, and I/O
- **`src/TestConfig.zig`**: JSON test suite parsing; defines `TestSuite`, `TestEntry`, `TestType` enums

### Core Architectural Patterns

#### Memory Banking (Mapper Support)
The emulator supports multiple cartridge types:
- **Mapper.None**: ROM-only (32 KB fixed)
- **Mapper.MBC1**: Simple bank switching (up to 2 MB ROM, optional RAM)
- **Mapper.MBC3**: Advanced banking with RTC support

Memory.zig handles:
- ROM bank switching via writes to `0x2000-0x3FFF` (MBC1/MBC3)
- External RAM bank switching via `0x4000-0x5FFF`
- Banking mode (ROM vs RAM) via `0x6000-0x7FFF`
- All Game Boy memory regions (VRAM, WRAM, OAM, I/O, HRAM)

#### Test Suite (JSON-Driven)
- **File**: `test_suite.json` (75 test entries, IDs 0-74)
- **Parsed by**: `TestConfig.zig` using `std.json.parseFromSlice()`
- **Test Types**: `boot_rom`, `doctor_test`, `display_test`, `game`
- **Status tracking**: Each test has `pass_status` (passed, failed, crashed, unknown)
- **Directory convention**: Test output goes to `output/{test_id:02}/` (e.g., `output/07/`); custom ROMs use `output/{sanitized_rom_name}/`

#### Execution Modes
1. **Gameboy-Doctor Mode** (default for CPU tests)
   - Runs CPU cycles and logs state for external validation
   - Used with CPU instruction tests
   - Output piped to gameboy-doctor for comparison

2. **Display Mode** (for graphics tests and games)
   - Runs SDL2 window with real-time rendering
   - Handles joypad input
   - Supports save/load state and automatic RAM persistence
   - Frames sync at ~60 FPS (configurable with `--fast`)

### Zig 0.15 Compatibility Notes
- **JSON parsing**: Use `std.json.parseFromSlice()`, not `Parser.init()`
- **ArrayList**: Direct `allocator.alloc()` preferred over `std.ArrayList.Managed()` to avoid type complexity
- **File I/O**: Must pre-allocate stdout buffer before using `file.writer(buffer)` (see main.zig:17)
- **Memory management**: All allocated strings and slices require explicit `deinit()` calls

## Important Implementation Details

### Test Suite Lifetime & Memory Management
- TestSuite struct owns all test entry strings (path, name, notes)
- Must call `test_suite.deinit()` to free all allocations
- JSON value is separately deferred-deinit'd

### CLI Argument Parsing
- Uses custom parsing loop in main.zig (lines 35-60)
- Requires either `--test <id>` or `--rom <path>` (error otherwise)
- Test type determines execution flow (display vs doctor mode)

### File Path Generation
- `utils.getFilePath()` generates output paths based on test number or custom ROM name
- `utils.sanitizeFilename()` converts ROM paths to safe directory names (basename, remove extension, replace non-alphanumeric with `_`)
- Output directories auto-created if missing

### Gameboy-Doctor Integration
- Used for CPU cycle-accurate instruction tests
- Emulator logs CPU state after each instruction
- Output format: `A:XX F:XX B:XX C:XX D:XX E:XX H:XX L:XX SP:XXXX PC:XXXX PCMEM:XX,XX,XX,XX`
- External tool validates against expected behavior

### State Persistence
- RAM auto-saves on shutdown if `ram_save_requested` flag set
- Save states stored via `cpu.saveState()` (keybind: U)
- Load states via `cpu.loadState()` (keybind: L)
- RAM saves via `cpu.saveRam()` (keybind: R)

## Display Mode Controls (SDL2)
- **S**: A button
- **A**: B button
- **Arrow Keys**: D-Pad
- **Return**: Start button
- **Right Shift**: Select button
- **D**: Toggle debug output
- **P / ESC**: Pause/unpause
- **R**: Save RAM
- **U**: Save state
- **L**: Load state
- **Q**: Quit

## Development Workflow

### Adding a New Test
1. Add entry to `test_suite.json` with unique `test_id`, `path`, `name`, `type`, `pass_status`, `notes`
2. Run `zig build run -- --test <id>` to execute
3. Monitor output in Gameboy-Doctor mode or watch SDL2 display

### Debugging CPU Issues
- Use `--test <id> --verbose` to see all CPU state changes
- Use `--test <id> --debug` for additional debug output
- Use `--log` to write detailed execution log (check `output/output.log`)
- Use `--mem` to dump memory state (implement in CPU.logState())

### Profiling Performance
- `--fast` flag runs at 2x speed (useful for longer tests)
- Frame rate shown in display mode (target 60 FPS)
- Use `std.time.Instant` for timing measurements (see main.zig display loop)

## Testing & Validation

### CPU Instruction Tests
- Run via `zig build test` (unit tests in respective modules)
- Gameboy-Doctor validates instruction accuracy
- Currently passing early boot and memory timing tests

### Display Tests
- Verify graphics rendering with `--test <id> --display`
- Check tilemap, sprite rendering, scrolling, window layer
- Boot ROM verification (test #0) shows Nintendo logo and initial state

## Dependencies
- **SDL2**: Graphics and event handling (linked dynamically via `build.zig`)
- **SDL2_ttf**: Font rendering for FPS display
- **zeit**: Time/clock library for RTC emulation (git: https://github.com/rockorager/zeit)

## Key Files by Purpose

| Purpose | Files |
|---------|-------|
| Execution loop | main.zig, Cpu.zig, Memory.zig |
| Graphics | PPU.zig, display/ |
| Input | Joypad.zig, io/ |
| Timing | Timer.zig, cpu/ |
| Banking | Memory.zig, RomBank.zig, utils.zig (Mapper enum) |
| I/O & Debug | utils.zig (file ops), Cpu.zig (logging) |
| Test infrastructure | TestConfig.zig, test_suite.json |

## Recent Refactoring Notes
- Boot ROM support removed (commit 984d78e)
- Hard-coded ROM paths replaced with JSON test suite (commit 8c43755)
- Output logging fixed (commit 55b9044)
- Writer/reader code upgraded for Zig 0.15 compatibility (commit 5523103)
