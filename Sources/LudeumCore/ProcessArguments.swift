import Darwin

/// A running process's command line.
public enum ProcessArguments {
    /// The arguments `pid` was started with, its executable's first, or nil if it isn't running or can't be read.
    public static func of(_ pid: pid_t) -> [String]? {
        var mib: [Int32] = [CTL_KERN, KERN_ARGMAX]
        var argMax: Int32 = 0
        var size = MemoryLayout<Int32>.size
        guard sysctl(&mib, 2, &argMax, &size, nil, 0) == 0, argMax > 0 else { return nil }
        // An int argc, the executable's path, padding, then argc NUL-terminated arguments, then the environment.
        var buffer = [UInt8](repeating: 0, count: Int(argMax))
        mib = [CTL_KERN, KERN_PROCARGS2, pid]
        size = buffer.count
        guard sysctl(&mib, 3, &buffer, &size, nil, 0) == 0, size > MemoryLayout<Int32>.size else { return nil }
        let argc = buffer.withUnsafeBytes { Int($0.loadUnaligned(as: Int32.self)) }
        var i = MemoryLayout<Int32>.size
        while i < size, buffer[i] != 0 { i += 1 }
        while i < size, buffer[i] == 0 { i += 1 }
        var arguments: [String] = []
        while arguments.count < argc, i < size {
            let start = i
            while i < size, buffer[i] != 0 { i += 1 }
            arguments.append(String(decoding: buffer[start..<i], as: UTF8.self))
            i += 1
        }
        return arguments.count == argc ? arguments : nil
    }
}
