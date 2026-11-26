// Adapted from baa by Selvi Arora (MIT). See NOTICE.
import Foundation
import Darwin

enum Mem {
    static func int32(_ name: String) -> Int {
        var v: Int32 = 0; var s = MemoryLayout<Int32>.size
        sysctlbyname(name, &v, &s, nil, 0); return Int(v)
    }
    static var freePct: Int { int32("kern.memorystatus_level") }          // what memory_pressure calls "free percentage"
    static var level: Int { int32("kern.memorystatus_vm_pressure_level") } // 1 normal, 2 warn, 4 critical
    static var swapGB: Double {
        var x = xsw_usage(); var s = MemoryLayout<xsw_usage>.size
        sysctlbyname("vm.swapusage", &x, &s, nil, 0); return Double(x.xsu_used) / 1_073_741_824
    }
    // the same split Activity Monitor shows, so the panel can say where the RAM actually went
    struct Breakdown {
        var total = 0.0, apps = 0.0, wired = 0.0, compressed = 0.0, cached = 0.0, free = 0.0
        var squeezed = 0.0 // app memory before compression; it's packed into `compressed`
    }
    static var breakdown: Breakdown {
        var total: UInt64 = 0; var ts = MemoryLayout<UInt64>.size
        sysctlbyname("hw.memsize", &total, &ts, nil, 0)
        var s = vm_statistics64()
        var n = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.size / MemoryLayout<integer_t>.size)
        let ok = withUnsafeMutablePointer(to: &s) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(n)) { host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &n) }
        }
        guard ok == KERN_SUCCESS else { return Breakdown(total: Double(total)) }
        let pg = Double(getpagesize())
        var b = Breakdown(total: Double(total))
        b.apps = Double(s.internal_page_count - s.purgeable_count) * pg
        b.wired = Double(s.wire_count) * pg
        b.compressed = Double(s.compressor_page_count) * pg
        b.cached = Double(s.external_page_count + s.purgeable_count) * pg
        b.free = max(0, b.total - b.apps - b.wired - b.compressed - b.cached)
        b.squeezed = Double(s.total_uncompressed_pages_in_compressor) * pg
        return b
    }
}

@discardableResult
func run(_ path: String, _ args: [String]) -> (out: String, status: Int32) {
    let p = Process(); p.executableURL = URL(fileURLWithPath: path); p.arguments = args
    let pipe = Pipe(); p.standardOutput = pipe; p.standardError = FileHandle.nullDevice
    do { try p.run() } catch { return ("", -1) }
    let d = pipe.fileHandleForReading.readDataToEndOfFile(); p.waitUntilExit()
    return (String(decoding: d, as: UTF8.self), p.terminationStatus)
}

func dur(_ s: Double) -> String {
    let m = Int(s / 60); if m < 60 { return "\(m)m" }
    let h = m / 60; if h >= 48 { return "\(h / 24)d" }
    return (m % 60 == 0 || h >= 10) ? "\(h)h" : "\(h)h \(m % 60)m"
}

func size(_ b: Double) -> String {
    b >= 1_073_741_824 ? String(format: "%.1f GB", b / 1_073_741_824) : "\(Int(b / 1_048_576)) MB"
}

// CMD_FAST=1 turns every "N minutes" threshold into N seconds (for testing)
let fast = ProcessInfo.processInfo.environment["CMD_FAST"] != nil
func mins(_ m: Double) -> Double { fast ? m : m * 60 }
