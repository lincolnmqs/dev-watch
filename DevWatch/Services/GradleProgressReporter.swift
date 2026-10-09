import Foundation

/// Installs a small Gradle init script that reports task progress to DevWatch.
///
/// Gradle loads every script in `~/.gradle/init.d`, so once installed, any Gradle build
/// (terminal, React Native, Flutter, Android Studio) writes a JSON progress file into
/// `~/Library/Application Support/DevWatch/builds`, which `BuildScanner` reads.
enum GradleProgressReporter {
    static let scriptVersion = 1

    static var progressDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/DevWatch/builds", isDirectory: true)
    }

    static var scriptURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".gradle/init.d/devwatch-progress.gradle")
    }

    static var isInstalled: Bool {
        FileManager.default.fileExists(atPath: scriptURL.path)
    }

    static func install() throws {
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: scriptURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try fileManager.createDirectory(at: progressDirectory, withIntermediateDirectories: true)
        try script.write(to: scriptURL, atomically: true, encoding: .utf8)
    }

    static func uninstall() throws {
        guard isInstalled else { return }
        try FileManager.default.removeItem(at: scriptURL)
    }

    /// Rewrites the script when a newer DevWatch ships a different version.
    static func upgradeIfNeeded() {
        guard isInstalled,
              let current = try? String(contentsOf: scriptURL, encoding: .utf8),
              current != script else { return }
        try? install()
    }

    static let script = """
    // Installed by DevWatch (v\(scriptVersion)) — reports Gradle task progress to the DevWatch menu bar app.
    // Disable it from DevWatch Settings or simply delete this file.
    import org.gradle.api.provider.Property
    import org.gradle.api.services.BuildService
    import org.gradle.api.services.BuildServiceParameters
    import org.gradle.build.event.BuildEventsListenerRegistry
    import org.gradle.tooling.events.FinishEvent
    import org.gradle.tooling.events.OperationCompletionListener
    import org.gradle.tooling.events.task.TaskFailureResult
    import org.gradle.tooling.events.task.TaskFinishEvent

    import javax.inject.Inject
    import java.nio.charset.StandardCharsets
    import java.nio.file.Files
    import java.nio.file.Path
    import java.nio.file.Paths
    import java.nio.file.StandardCopyOption

    abstract class DevWatchProgressService implements BuildService<Params>, OperationCompletionListener, AutoCloseable {
        interface Params extends BuildServiceParameters {
            Property<String> getProjectName()
            Property<String> getProjectDir()
            Property<String> getTasks()
            Property<Integer> getTotalTasks()
        }

        private String buildId
        private long startedAt
        private int completed = 0
        private int failed = 0
        private String currentTask = ""
        private long lastWrite = 0

        private void ensureStarted() {
            if (buildId != null) return
            buildId = UUID.randomUUID().toString()
            startedAt = System.currentTimeMillis()
        }

        @Override
        synchronized void onFinish(FinishEvent event) {
            if (!(event instanceof TaskFinishEvent)) return
            ensureStarted()
            completed++
            if (event.result instanceof TaskFailureResult) failed++
            currentTask = event.descriptor.taskPath
            long now = System.currentTimeMillis()
            if (now - lastWrite >= 250) {
                lastWrite = now
                write("running")
            }
        }

        @Override
        synchronized void close() {
            if (buildId == null) return
            int total = parameters.totalTasks.getOrElse(0)
            String state = failed > 0 ? "failed" : (completed >= total ? "succeeded" : "cancelled")
            write(state)
        }

        private void write(String state) {
            try {
                Path dir = Paths.get(System.getProperty("user.home"), "Library", "Application Support", "DevWatch", "builds")
                Files.createDirectories(dir)
                long now = System.currentTimeMillis()
                String json = "{" +
                    "\\"id\\":" + quote(buildId) + "," +
                    "\\"pid\\":" + ProcessHandle.current().pid() + "," +
                    "\\"projectName\\":" + quote(parameters.projectName.getOrElse("")) + "," +
                    "\\"projectDir\\":" + quote(parameters.projectDir.getOrElse("")) + "," +
                    "\\"tasks\\":" + quote(parameters.tasks.getOrElse("")) + "," +
                    "\\"startedAt\\":" + startedAt + "," +
                    "\\"updatedAt\\":" + now + "," +
                    "\\"completed\\":" + completed + "," +
                    "\\"total\\":" + parameters.totalTasks.getOrElse(0) + "," +
                    "\\"failed\\":" + failed + "," +
                    "\\"currentTask\\":" + quote(currentTask) + "," +
                    "\\"state\\":" + quote(state) +
                    "}"
                Path tmp = dir.resolve(buildId + ".json.tmp")
                Files.write(tmp, json.getBytes(StandardCharsets.UTF_8))
                Files.move(tmp, dir.resolve(buildId + ".json"), StandardCopyOption.REPLACE_EXISTING, StandardCopyOption.ATOMIC_MOVE)
            } catch (Exception ignored) {
                // Progress reporting must never break a build.
            }
        }

        private static String quote(String value) {
            StringBuilder builder = new StringBuilder("\\"")
            for (char c : (value ?: "").toCharArray()) {
                if (c == '"' as char || c == '\\\\' as char) builder.append('\\\\').append(c)
                else if (c < 0x20) builder.append(String.format("\\\\u%04x", (int) c))
                else builder.append(c)
            }
            return builder.append('"').toString()
        }
    }

    abstract class DevWatchProgressPlugin implements Plugin<Gradle> {
        @Inject
        abstract BuildEventsListenerRegistry getRegistry()

        @Override
        void apply(Gradle gradle) {
            // Only the root build reports; included builds and buildSrc share its progress.
            if (gradle.parent != null) return

            gradle.settingsEvaluated { settings ->
                def service = gradle.sharedServices.registerIfAbsent("portWatchProgress", DevWatchProgressService) { spec ->
                    spec.parameters.projectName.set(settings.rootProject.name)
                    spec.parameters.projectDir.set(settings.rootDir.absolutePath)
                    spec.parameters.tasks.set(gradle.startParameter.taskNames.join(" "))
                    spec.parameters.totalTasks.set(settings.providers.provider { gradle.taskGraph.allTasks.size() })
                }
                registry.onTaskCompletion(service)
            }
        }
    }

    apply plugin: DevWatchProgressPlugin

    """
}
