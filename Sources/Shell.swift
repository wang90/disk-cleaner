import Foundation

/// 执行 /bin/bash diskautoclean.sh，并把输出按行回调出来。
enum Shell {

    static let bashPath = "/bin/bash"

    /// 执行并捕获「全部标准输出」（用于 --json 查询）
    ///
    /// 注意：必须一边写一边读。如果等进程结束再 readDataToEndOfFile()，
    /// 子进程输出超过管道缓冲区（约 64KB）时会阻塞，父进程又在等它结束，
    /// 就会死锁。
    static func capture(script: URL,
                        args: [String],
                        extraEnv: [String: String] = [:]) async -> (code: Int32, stdout: String) {
        await withCheckedContinuation { (cont: CheckedContinuation<(Int32, String), Never>) in
            let p = Process()
            p.executableURL = URL(fileURLWithPath: bashPath)
            p.arguments = [script.path] + args
            p.environment = baseEnv(extra: extraEnv)

            let out = Pipe()
            let err = Pipe()
            p.standardOutput = out
            p.standardError = err

            let box = DataBox()
            let sink = DataBox()   // stderr 丢弃，但必须持续读走
            out.fileHandleForReading.readabilityHandler = { handle in
                let d = handle.availableData
                if !d.isEmpty { box.append(d) }
            }
            err.fileHandleForReading.readabilityHandler = { handle in
                let d = handle.availableData
                if !d.isEmpty { sink.append(d) }
            }

            p.terminationHandler = { proc in
                out.fileHandleForReading.readabilityHandler = nil
                err.fileHandleForReading.readabilityHandler = nil
                box.append(out.fileHandleForReading.availableData)
                cont.resume(returning: (proc.terminationStatus,
                                       String(data: box.value(), encoding: .utf8) ?? ""))
            }
            do {
                try p.run()
            } catch {
                out.fileHandleForReading.readabilityHandler = nil
                err.fileHandleForReading.readabilityHandler = nil
                cont.resume(returning: (-1, ""))
            }
        }
    }

    /// 流式执行，stdout + stderr 合并后逐行回调（用于清理过程）
    static func stream(script: URL,
                       args: [String],
                       extraEnv: [String: String] = [:],
                       onLine: @escaping (String) -> Void) async -> Int32 {
        await withCheckedContinuation { (cont: CheckedContinuation<Int32, Never>) in
            let p = Process()
            p.executableURL = URL(fileURLWithPath: bashPath)
            p.arguments = [script.path] + args
            p.environment = baseEnv(extra: extraEnv)

            let pipe = Pipe()
            p.standardOutput = pipe
            p.standardError = pipe

            let buffer = LineBuffer()
            pipe.fileHandleForReading.readabilityHandler = { handle in
                let data = handle.availableData
                guard !data.isEmpty else { return }
                for line in buffer.append(data) { onLine(line) }
            }

            p.terminationHandler = { proc in
                pipe.fileHandleForReading.readabilityHandler = nil
                for line in buffer.flush() { onLine(line) }
                cont.resume(returning: proc.terminationStatus)
            }
            do {
                try p.run()
            } catch {
                pipe.fileHandleForReading.readabilityHandler = nil
                cont.resume(returning: -1)
            }
        }
    }

    /// 直接运行一个系统小工具（launchctl / open 等）
    @discardableResult
    static func runTool(_ path: String, _ args: [String]) async -> Int32 {
        await withCheckedContinuation { (cont: CheckedContinuation<Int32, Never>) in
            let p = Process()
            p.executableURL = URL(fileURLWithPath: path)
            p.arguments = args
            p.environment = baseEnv()
            let pipe = Pipe()
            p.standardOutput = pipe
            p.standardError = pipe
            p.terminationHandler = { proc in
                _ = pipe.fileHandleForReading.readDataToEndOfFile()
                cont.resume(returning: proc.terminationStatus)
            }
            do { try p.run() } catch { cont.resume(returning: -1) }
        }
    }

    static func baseEnv(extra: [String: String] = [:]) -> [String: String] {
        var env = ProcessInfo.processInfo.environment
        env["PATH"] = "/usr/bin:/bin:/usr/sbin:/sbin:/usr/local/bin:/opt/homebrew/bin"
        env["LANG"] = "zh_CN.UTF-8"
        for (k, v) in extra { env[k] = v }
        return env
    }
}

/// 线程安全的字节累积器（用于边写边读地收集子进程输出）
final class DataBox {
    private var data = Data()
    private let lock = NSLock()

    func append(_ chunk: Data) {
        guard !chunk.isEmpty else { return }
        lock.lock(); data.append(chunk); lock.unlock()
    }

    func value() -> Data {
        lock.lock(); defer { lock.unlock() }
        return data
    }
}

/// 线程安全的按行切分缓冲
final class LineBuffer {
    private var data = Data()
    private let lock = NSLock()

    func append(_ chunk: Data) -> [String] {
        lock.lock(); defer { lock.unlock() }
        data.append(chunk)
        var lines: [String] = []
        while let idx = data.firstIndex(of: 0x0A) {
            let sub = data.subdata(in: data.startIndex..<idx)
            data.removeSubrange(data.startIndex...idx)
            if let s = String(data: sub, encoding: .utf8) { lines.append(s) }
        }
        return lines
    }

    func flush() -> [String] {
        lock.lock(); defer { lock.unlock() }
        guard !data.isEmpty else { return [] }
        let s = String(data: data, encoding: .utf8) ?? ""
        data.removeAll()
        return s.isEmpty ? [] : [s]
    }
}
