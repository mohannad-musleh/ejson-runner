pub fn SliceIterator(comptime T: type) type {
    const S = []const T;

    return struct {
        const Self = @This();

        slice: S,
        index: usize,

        pub fn init(slice: S) Self {
            return .{
                .slice = slice,
                .index = 0,
            };
        }

        pub fn reset(self: *Self) void {
            self.index = 0;
        }

        pub fn next(self: *Self) ?T {
            if (self.index >= self.slice.len) {
                return null;
            }

            const item = self.slice[self.index];
            self.index += 1;
            return item;
        }

        pub fn peek(self: *Self) ?T {
            if (self.index >= self.slice.len) {
                return null;
            }

            const item = self.slice[self.index];
            return item;
        }
    };
}

pub const SliceOfStringsIterator = SliceIterator([]const u8);
