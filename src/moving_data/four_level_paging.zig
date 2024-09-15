const VirtualAddress = extern union {
    page_4k: Page4k,
    page_2m: Page2M,
    page_1g: Page1G,

    const Page4k = packed struct {
        offset: u12,
        table_idx: u9,
        directory_idx: u9,
        directory_ptr_idx: u9,
        pml4idx: u9,
        padding: u16,

        pub fn format(self: Page4k, comptime _: []const u8, _: std.fmt.FormatOptions, writer: anytype) !void {
            try writer.print(
                "4K address  | {d:>3} | {d:>3} | {d:>3} | {d:>3} | {d:>10}|",
                .{ self.pml4idx, self.directory_ptr_idx, self.directory_idx, self.table_idx, self.offset },
            );
        }
    };
    const Page2M = packed struct {
        offset: u21,
        directory_idx: u9,
        directory_ptr_idx: u9,
        pml4idx: u9,
        padding: u16,

        pub fn format(self: Page2M, comptime _: []const u8, _: std.fmt.FormatOptions, writer: anytype) !void {
            try writer.print(
                "2M address  | {d:>3} | {d:>3} | {d:>3} | {d:>3} | {d:>10}|",
                .{ self.pml4idx, self.directory_ptr_idx, self.directory_idx, 0, self.offset },
            );
        }
    };
    const Page1G = packed struct {
        offset: u30,
        directory_ptr_idx: u9,
        pml4idx: u9,
        padding: u16,

        pub fn format(self: Page1G, comptime _: []const u8, _: std.fmt.FormatOptions, writer: anytype) !void {
            try writer.print(
                "1G address  | {d:>3} | {d:>3} | {d:>3} | {d:>3} | {d:>10}|",
                .{ self.pml4idx, self.directory_ptr_idx, 0, 0, self.offset },
            );
        }
    };
};

fn decompose_virtual_address(pointer: u64) VirtualAddress {
    var address: VirtualAddress = undefined;
    address.page_4k.padding = @truncate(pointer >> 48);
    address.page_4k.pml4idx = @truncate((pointer >> 39) & 0x1ff);
    address.page_4k.directory_ptr_idx = @truncate((pointer >> 30) & 0x1ff);
    address.page_4k.directory_idx = @truncate((pointer >> 21) & 0x1ff);
    address.page_4k.table_idx = @truncate((pointer >> 12) & 0x1ff);
    address.page_4k.offset = @truncate((pointer >> 0) & 0xfff);
    return address;
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    defer {
        const deinit_code = gpa.deinit();
        if (deinit_code == .leak) @panic("Leaked memory");
    }

    var args = try std.process.argsWithAllocator(allocator);
    defer args.deinit();

    _ = args.next() orelse {
        std.log.err("UNEXPECTED MISSING ZIG\n", .{});
        return;
    };

    for (0..16) |_| {
        const pointer = windows.kernel32.VirtualAlloc(null, 1024 * 1024, windows.MEM_RESERVE | windows.MEM_COMMIT, windows.PAGE_READWRITE).?;
        defer {
            _ = windows.kernel32.VirtualFree(pointer, 1024 * 1024, windows.MEM_RELEASE);
        }
        print_virtual_address(@intFromPtr(pointer));
        const address = decompose_virtual_address(@intFromPtr(pointer));
        std.debug.print("{s}\n", .{address.page_4k});
        std.debug.print("{s}\n", .{address.page_2m});
        std.debug.print("{s}\n", .{address.page_1g});
        std.debug.print("\n", .{});
    }
}

pub fn print_virtual_address(pointer: u64) void {
    std.debug.print("Address: ", .{});
    std.debug.print("0b{b:0>16}", .{(pointer >> 48)});
    std.debug.print(" | {b:0>9}", .{(pointer >> 39) & 0x1ff});
    std.debug.print(" | {b:0>9}", .{(pointer >> 30) & 0x1ff});
    std.debug.print(" | {b:0>9}", .{(pointer >> 21) & 0x1ff});
    std.debug.print(" | {b:0>9}", .{(pointer >> 12) & 0x1ff});
    std.debug.print(" | {b:0>12}\n", .{(pointer >> 0) & 0xfff});
}

const std = @import("std");
const windows = std.os.windows;
