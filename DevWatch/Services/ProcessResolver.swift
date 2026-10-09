import Darwin
import Foundation

struct ProcessResolver {
    static func startTime(for pid: Int) -> Date? {
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, Int32(pid)]
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        guard sysctl(&mib, 4, &info, &size, nil, 0) == 0, size > 0 else { return nil }
        let tv = info.kp_proc.p_starttime
        return Date(timeIntervalSince1970: TimeInterval(tv.tv_sec) + TimeInterval(tv.tv_usec) / 1_000_000)
    }

    static func executablePath(for pid: Int) -> String? {
        var buffer = [CChar](repeating: 0, count: Int(MAXPATHLEN * 4))
        guard proc_pidpath(Int32(pid), &buffer, UInt32(buffer.count)) > 0 else { return nil }
        return String(cString: buffer)
    }

    static func workingDirectory(for pid: Int) -> String? {
        var info = proc_vnodepathinfo()
        let size = Int32(MemoryLayout<proc_vnodepathinfo>.size)
        guard proc_pidinfo(Int32(pid), PROC_PIDVNODEPATHINFO, 0, &info, size) > 0 else { return nil }
        return withUnsafePointer(to: &info.pvi_cdir.vip_path) { ptr in
            ptr.withMemoryRebound(to: CChar.self, capacity: Int(MAXPATHLEN)) {
                let s = String(cString: $0)
                return s.isEmpty ? nil : s
            }
        }
    }

    static func commandLine(for pid: Int) -> [String]? {
        var argmax = 0
        var argmaxSize = MemoryLayout<Int>.size
        var mibArgmax: [Int32] = [CTL_KERN, KERN_ARGMAX]
        guard sysctl(&mibArgmax, 2, &argmax, &argmaxSize, nil, 0) == 0, argmax > 0 else { return nil }

        var mib: [Int32] = [CTL_KERN, KERN_PROCARGS2, Int32(pid)]
        var buffer = [UInt8](repeating: 0, count: argmax)
        var bufferSize = argmax
        guard sysctl(&mib, 3, &buffer, &bufferSize, nil, 0) == 0, bufferSize > 4 else { return nil }

        let argc = buffer.withUnsafeBytes { $0.load(as: Int32.self) }
        var index = 4

        // Skip executable path
        while index < bufferSize && buffer[index] != 0 { index += 1 }
        while index < bufferSize && buffer[index] == 0 { index += 1 }

        var args: [String] = []
        for _ in 0..<max(0, Int(argc)) {
            guard index < bufferSize else { break }
            let start = index
            while index < bufferSize && buffer[index] != 0 { index += 1 }
            if let s = String(bytes: buffer[start..<index], encoding: .utf8), !s.isEmpty {
                args.append(s)
            }
            index += 1
        }

        return args.isEmpty ? nil : args
    }
}
