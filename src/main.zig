const std = @import("std");
const Io = std.Io;
const log = std.log;
const net = std.Io.net;

const zighook = @import("zighook");

pub fn main(init: std.process.Init) !void {
    const arena: std.mem.Allocator = init.arena.allocator();

    // Accessing command line arguments:
    const args = try init.minimal.args.toSlice(arena);

    if (args.len != 2) {
        log.err("Usage: zighook PORT", .{});
        std.process.exit(64);
    }

    const port = try std.fmt.parseInt(u16, args[1], 10);

    const io = init.io;
    var group: std.Io.Group = .init;
    defer group.cancel(io);

    log.info("Starting webserver on port {d}", .{port});
    const addr = try net.IpAddress.parse("127.0.0.1", port);
    var server = try addr.listen(io, .{ .reuse_address = true });

    while (true) {
        const stream = server.accept(io) catch |err| {
            log.err("failed to accept connection: {s}", .{@errorName(err)});
            continue;
        };

        group.async(io, accept, .{ stream, io, arena });
    }
}

const EventType = enum {
    PUSH,
    UNKNOWN,
};

const sigLen = 64;
const emptySig: [sigLen]u8 = @splat(' ');

const HookHeaders = struct {
    event: EventType,
    signature: [sigLen]u8,
    isJson: bool,

    pub fn init() HookHeaders {
        return HookHeaders{
            .event = .UNKNOWN,
            .signature = emptySig,
            .isJson = false,
        };
    }

    pub fn isValid(headers: HookHeaders) bool {
        return headers.event == .PUSH and headers.isJson and
            !(std.mem.eql(u8, &headers.signature, &emptySig));
    }
};

fn parseHookHeaders(req: *const std.http.Server.Request) HookHeaders {
    const eventHeader = "x-github-event";
    const sha256Header = "x-hub-signature-256";

    var res: HookHeaders = .init();
    var iter = req.iterateHeaders();
    while (iter.next()) |h| {
        if (std.ascii.eqlIgnoreCase(eventHeader, h.name) and std.ascii.eqlIgnoreCase(h.value, "push")) {
            res.event = .PUSH;
        } else if (std.ascii.eqlIgnoreCase(sha256Header, h.name)) {
            var hash = std.mem.splitSequence(u8, h.value, "sha256=");
            _ = hash.first();
            if (hash.rest().len == sigLen) {
                @memmove(&res.signature, hash.rest()[0..res.signature.len]);
            }
        } else if (std.ascii.eqlIgnoreCase("content-type", h.name) and std.ascii.eqlIgnoreCase("application/json", h.value)) {
            res.isJson = true;
        }
    }

    return res;
}

fn accept(stream: net.Stream, io: Io, alloc: std.mem.Allocator) error{Canceled}!void {
    var arena: std.heap.ArenaAllocator = .init(alloc);
    defer arena.deinit();

    defer stream.close(io);

    log.info("Got new client", .{});

    var source_buffer: [8192]u8 = undefined;
    var sink_buffer: [1024]u8 = undefined;
    var source_reader = stream.reader(io, &source_buffer);
    var sink_writer = stream.writer(io, &sink_buffer);
    var server = std.http.Server.init(&source_reader.interface, &sink_writer.interface);

    while (server.reader.state == .ready) {
        var request = server.receiveHead() catch {
            break;
        };

        switch (request.upgradeRequested()) {
            .none => {},
            else => {
                log.err("updated requested but we do not support {s}", .{@tagName(request.upgradeRequested())});
            },
        }

        const hHeaders = parseHookHeaders(&request);
        if (hHeaders.isValid()) {
            log.info("got valid header, reading body", .{});
            server.reader.bodyReaderDecompressing(transfer_buffer: []u8, transfer_encoding: TransferEncoding, content_length: ?u64, content_encoding: ContentEncoding, decompress: *Decompress, decompress_buffer: []u8)
        }

        // lets just send ok
        request.respond("Hello world", .{}) catch |err| {
            log.err("error sending response: {s}", .{@errorName(err)});
        };
    }
    log.info("reader state: {s}", .{@tagName(server.reader.state)});
    log.info("handler thread exited", .{});
}
