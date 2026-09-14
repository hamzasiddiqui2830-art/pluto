const std = @import("std");
const Allocator = std.mem.Allocator;
const log = std.log.scoped(.x86_64_keyboard);
const arch = @import("arch.zig");
const Keyboard = @import("../../keyboard.zig").Keyboard;

/// PS/2 keyboard ports.
const PS2_DATA_PORT: u16 = 0x60;
const PS2_STATUS_PORT: u16 = 0x64;
const PS2_COMMAND_PORT: u16 = 0x64;

/// PS/2 commands.
const PS2_CMD_WRITE_OUTPUT_BUFFER: u8 = 0xD2;
const PS2_CMD_ENABLE_FIRST_PORT: u8 = 0xAE;
const PS2_CMD_DISABLE_FIRST_PORT: u8 = 0xAD;
const PS2_CMD_READ_CONFIG: u8 = 0x20;
const PS2_CMD_WRITE_CONFIG: u8 = 0x60;

/// Scancode set 1 make codes.
const SCANCODE_ESCAPE: u8 = 0x01;
const SCANCODE_BACKSPACE: u8 = 0x0E;
const SCANCODE_TAB: u8 = 0x0F;
const SCANCODE_ENTER: u8 = 0x1C;
const SCANCODE_CTRL: u8 = 0x1D;
const SCANCODE_SHIFT_LEFT: u8 = 0x2A;
const SCANCODE_SHIFT_RIGHT: u8 = 0x36;
const SCANCODE_ALT: u8 = 0x38;
const SCANCODE_CAPS_LOCK: u8 = 0x3A;
const SCANCODE_F1: u8 = 0x3B;
const SCANCODE_F12: u8 = 0x57;

/// Key states.
var shift_pressed: bool = false;
var ctrl_pressed: bool = false;
var alt_pressed: bool = false;
var caps_lock: bool = false;

/// Scancode to ASCII mapping (US QWERTY).
const scancode_to_ascii: [59]u8 = .{
    0, // 0x00
    27, // 0x01 Escape
    '1', // 0x02
    '2', // 0x03
    '3', // 0x04
    '4', // 0x05
    '5', // 0x06
    '6', // 0x07
    '7', // 0x08
    '8', // 0x09
    '9', // 0x0A
    '0', // 0x0B
    '-', // 0x0C
    '=', // 0x0D
    8, // 0x0E Backspace
    9, // 0x0F Tab
    'q', // 0x10
    'w', // 0x11
    'e', // 0x12
    'r', // 0x13
    't', // 0x14
    'y', // 0x15
    'u', // 0x16
    'i', // 0x17
    'o', // 0x18
    'p', // 0x19
    '[', // 0x1A
    ']', // 0x1B
    13, // 0x1C Enter
    0, // 0x1D Ctrl
    'a', // 0x1E
    's', // 0x1F
    'd', // 0x20
    'f', // 0x21
    'g', // 0x22
    'h', // 0x23
    'j', // 0x24
    'k', // 0x25
    'l', // 0x26
    ';', // 0x27
    '\'', // 0x28
    '`', // 0x29
    0, // 0x2A Shift
    '\\', // 0x2B
    'z', // 0x2C
    'x', // 0x2D
    'c', // 0x2E
    'v', // 0x2F
    'b', // 0x30
    'n', // 0x31
    'm', // 0x32
    ',', // 0x33
    '.', // 0x34
    '/', // 0x35
    0, // 0x36 Shift
    '*', // 0x37
    0, // 0x38 Alt
    ' ', // 0x39 Space
    0, // 0x3A Caps Lock
};

/// Wait for keyboard controller to be ready.
fn waitForKeyboard() void {
    while ((arch.in(u8, PS2_STATUS_PORT) & 0x02) != 0) {
        arch.ioWait();
    }
}

/// Read a byte from the keyboard.
fn readByte() ?u8 {
    if ((arch.in(u8, PS2_STATUS_PORT) & 0x01) != 0) {
        return arch.in(u8, PS2_DATA_PORT);
    }
    return null;
}

/// Initialize the PS/2 keyboard.
pub fn init(allocator: Allocator) Allocator.Error!*Keyboard {
    log.info("Init\n", .{});
    defer log.info("Done\n", .{});

    // Disable keyboard temporarily
    arch.out(PS2_COMMAND_PORT, PS2_CMD_DISABLE_FIRST_PORT);

    // Clear output buffer
    while (readByte()) |_| {}

    // Enable keyboard
    arch.out(PS2_COMMAND_PORT, PS2_CMD_ENABLE_FIRST_PORT);

    const keyboard = try allocator.create(Keyboard);
    keyboard.* = .{
        .read = readKey,
        .peek = peekKey,
    };

    return keyboard;
}

/// Convert scancode to character.
fn scancodeToChar(scancode: u8) ?u8 {
    if (scancode >= scancode_to_ascii.len) {
        return null;
    }

    var ch = scancode_to_ascii[scancode];
    if (ch == 0) {
        return null;
    }

    // Handle modifiers
    if (shift_pressed) {
        if (ch >= 'a' and ch <= 'z') {
            ch = ch - 'a' + 'A';
        } else if (ch == '1') {
            ch = '!';
        } else if (ch == '2') {
            ch = '@';
        } else if (ch == '3') {
            ch = '#';
        } else if (ch == '4') {
            ch = '$';
        } else if (ch == '5') {
            ch = '%';
        } else if (ch == '6') {
            ch = '^';
        } else if (ch == '7') {
            ch = '&';
        } else if (ch == '8') {
            ch = '*';
        } else if (ch == '9') {
            ch = '(';
        } else if (ch == '0') {
            ch = ')';
        }
    }

    return ch;
}

/// Read a key from the keyboard.
fn readKey() ?u8 {
    while (true) {
        if (readByte()) |scancode| {
            // Check for key release (bit 7 set)
            const is_release = (scancode & 0x80) != 0;
            const key = scancode & 0x7F;

            // Handle modifier keys
            switch (key) {
                SCANCODE_SHIFT_LEFT, SCANCODE_SHIFT_RIGHT => {
                    shift_pressed = !is_release;
                    continue;
                },
                SCANCODE_CTRL => {
                    ctrl_pressed = !is_release;
                    continue;
                },
                SCANCODE_ALT => {
                    alt_pressed = !is_release;
                    continue;
                },
                SCANCODE_CAPS_LOCK => {
                    if (!is_release) {
                        caps_lock = !caps_lock;
                    }
                    continue;
                },
                else => {},
            }

            // Only process key presses, not releases
            if (is_release) {
                continue;
            }

            return scancodeToChar(key);
        }
        arch.halt();
    }
}

/// Peek at available key without consuming it.
fn peekKey() ?u8 {
    if (readByte()) |scancode| {
        // For now, just consume and return null
        // A proper implementation would buffer the key
        _ = scancode;
    }
    return null;
}

test "keyboard initialization" {
    // Mock test
}
