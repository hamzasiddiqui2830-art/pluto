const std = @import("std");
const log = std.log.scoped(.x86_64_rtc);
const arch = @import("arch.zig");

/// RTC ports.
const CMOS_ADDR: u16 = 0x70;
const CMOS_DATA: u16 = 0x71;

/// RTC registers.
const RTC_SECOND: u8 = 0x00;
const RTC_MINUTE: u8 = 0x02;
const RTC_HOUR: u8 = 0x04;
const RTC_DAY: u8 = 0x07;
const RTC_MONTH: u8 = 0x08;
const RTC_YEAR: u8 = 0x09;
const RTC_STATUS_A: u8 = 0x0A;
const RTC_STATUS_B: u8 = 0x0B;

/// Date/time structure.
pub const DateTime = struct {
    year: u16,
    month: u8,
    day: u8,
    hour: u8,
    minute: u8,
    second: u8,
};

/// Read from CMOS register.
fn cmosRead(reg: u8) u8 {
    arch.out(CMOS_ADDR, reg);
    return arch.in(u8, CMOS_DATA);
}

/// Write to CMOS register.
fn cmosWrite(reg: u8, value: u8) void {
    arch.out(CMOS_ADDR, reg);
    arch.out(CMOS_DATA, value);
}

/// Check if RTC update is in progress.
fn rtcUpdateInProgress() bool {
    return (cmosRead(RTC_STATUS_A) & 0x80) != 0;
}

/// Get current date and time from RTC.
pub fn getDateTime() DateTime {
    var sec: u8 = 0;
    var min: u8 = 0;
    var hour: u8 = 0;
    var day: u8 = 0;
    var month: u8 = 0;
    var year: u8 = 0;
    
    // Wait for update to finish, then read all values
    while (rtcUpdateInProgress()) {}
    
    sec = cmosRead(RTC_SECOND);
    min = cmosRead(RTC_MINUTE);
    hour = cmosRead(RTC_HOUR);
    day = cmosRead(RTC_DAY);
    month = cmosRead(RTC_MONTH);
    year = cmosRead(RTC_YEAR);
    
    // Check if we got interrupted during reading
    while (rtcUpdateInProgress()) {
        // Re-read if interrupted
        sec = cmosRead(RTC_SECOND);
        min = cmosRead(RTC_MINUTE);
        hour = cmosRead(RTC_HOUR);
        day = cmosRead(RTC_DAY);
        month = cmosRead(RTC_MONTH);
        year = cmosRead(RTC_YEAR);
    }
    
    // Check status B for BCD/binary mode
    const status_b = cmosRead(RTC_STATUS_B);
    const use_bcd = (status_b & 0x04) == 0;
    
    // Convert from BCD if necessary
    if (use_bcd) {
        sec = (sec & 0x0F) + ((sec / 16) * 10);
        min = (min & 0x0F) + ((min / 16) * 10);
        hour = (hour & 0x0F) + ((hour / 16) * 10);
        day = (day & 0x0F) + ((day / 16) * 10);
        month = (month & 0x0F) + ((month / 16) * 10);
        year = (year & 0x0F) + ((year / 16) * 10);
    }
    
    // Handle 12-hour format
    if ((status_b & 0x02) == 0) {
        // 12-hour format
        if ((hour & 0x80) != 0) {
            // PM
            hour = ((hour & 0x7F) + 12) % 24;
        } else {
            // AM
            hour = hour % 12;
        }
    } else {
        // 24-hour format, just clear the high bit
        hour = hour & 0x3F;
    }
    
    // Convert year to full year (assume 20xx for now)
    const full_year: u16 = 2000 + year;
    
    return .{
        .year = full_year,
        .month = month,
        .day = day,
        .hour = hour,
        .minute = min,
        .second = sec,
    };
}

/// Initialize RTC.
pub fn init() void {
    log.info("Init\\n", .{});
    defer log.info("Done\\n", .{});
    
    // Enable binary mode and 24-hour format
    const status_b = cmosRead(RTC_STATUS_B);
    cmosWrite(RTC_STATUS_B, status_b | 0x02 | 0x04);
}

test "RTC initialization" {
    init();
    const dt = getDateTime();
    try std.testing.expect(dt.year >= 2024);
    try std.testing.expect(dt.month >= 1 and dt.month <= 12);
    try std.testing.expect(dt.day >= 1 and dt.day <= 31);
}
