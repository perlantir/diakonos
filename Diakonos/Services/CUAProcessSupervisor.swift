import Foundation

/// Generic supervisor for a long-running child process. Used to spawn
/// `npx cuabot --serve`, the underlying cua sandbox server.
final class CUAProcessSupervisor: @unchecked Sendable {
    private let lock = NSLock()
    private var process: Process?
    private var stdoutPipe: Pipe?
    private var stderrPipe: Pipe?

    var isRunning: Bool {
        lock.lock(); defer { lock.unlock() }
        return process?.isRunning ?? false
    }

    /// Start the given executable with arguments. Returns immediately;
    /// caller polls `isRunning` or external state (e.g. HTTP `/status`).
    func start(executable: URL, arguments: [String], environment: [String: String]? = nil) throws {
        lock.lock(); defer { lock.unlock() }

        if let process, process.isRunning {
            return
        }

        let proc = Process()
        proc.executableURL = executable
        proc.arguments = arguments

        // Merge parent env with overrides so PATH (npx, docker) is found.
        var env = ProcessInfo.processInfo.environment
        if let environment {
            for (k, v) in environment { env[k] = v }
        }
        proc.environment = env

        let outPipe = Pipe()
        let errPipe = Pipe()
        proc.standardOutput = outPipe
        proc.standardError = errPipe

        proc.terminationHandler = { [weak self] _ in
            self?.lock.lock()
            self?.process = nil
            self?.stdoutPipe = nil
            self?.stderrPipe = nil
            self?.lock.unlock()
        }

        try proc.run()
        self.process = proc
        self.stdoutPipe = outPipe
        self.stderrPipe = errPipe
    }

    func terminate() {
        lock.lock(); defer { lock.unlock() }
        process?.terminate()
    }

    /// Asynchronously collect any pending stdout so far. Non-destructive after exit.
    func drainStdout() -> Data {
        lock.lock(); defer { lock.unlock() }
        return stdoutPipe?.fileHandleForReading.availableData ?? Data()
    }
}
