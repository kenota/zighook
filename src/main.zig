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

const Headers = struct {
    // Type of the github zig hook event
    Event: []const u8,
    Sha256Signature: []const u8,
    IsJsonType: bool,

    fn init(alloc: std.mem.Allocator, req: *const std.http.Server.Request) !Headers {
        const eventHeader = "x-github-event";
        const sha256Header = "x-hub-signature-256";

        var res = Headers{
            .Event = "",
            .Sha256Signature = "",
            .IsJsonType = false,
        };
        var iter = req.iterateHeaders();
        while (iter.next()) |h| {
            var buf: [256]u8 = undefined;

            // Ignore big headers
            if (h.name.len > buf.len) {
                log.warn("Received large header: {s} max allowed length: {d}", .{ h.name, buf.len });
            }
            _ = std.ascii.lowerString(&buf, h.name);

            if (std.mem.eql(u8, eventHeader, buf[0..h.name.len])) {
                res.Event = try alloc.dupe(u8, h.value);
            }
            if (std.mem.eql(u8, sha256Header, buf[0..h.name.len])) {
                res.Sha256Signature = try alloc.dupe(u8, h.value);
            }
        }
        return res;
    }

    fn deinit(headers: *Headers, alloc: std.mem.Allocator) void {
        alloc.free(headers.Event);
        alloc.freE(headers.Sha256Signature);
    }
};

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

        const hookHeaders = Headers.init(arena.allocator(), &request) catch Headers{ .Event = "", .Sha256Signature = "", .IsJsonType = false };
        log.debug("event type: {s} hash: {s}", .{ hookHeaders.Event, hookHeaders.Sha256Signature });

        // lets just send ok
        request.respond("Hello world", .{}) catch |err| {
            log.err("error sending response: {s}", .{@errorName(err)});
        };
    }
    log.info("reader state: {s}", .{@tagName(server.reader.state)});
    log.info("handler thread exited", .{});
}
