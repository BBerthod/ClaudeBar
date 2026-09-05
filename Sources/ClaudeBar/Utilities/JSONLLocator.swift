import Foundation

/// Shared discovery for Claude Code transcript files.
enum JSONLLocator {
    /// Returns every existing `~/.claude*/projects` directory.
    nonisolated static func allProjectsDirectories(
        homeDirectory: String = NSHomeDirectory()
    ) -> [String] {
        let fm = FileManager.default
        return ((try? fm.contentsOfDirectory(atPath: homeDirectory)) ?? [])
            .filter { $0 == ".claude" || $0.hasPrefix(".claude-") }
            .compactMap { name -> String? in
                let path = (homeDirectory as NSString)
                    .appendingPathComponent(name) + "/projects"
                var isDirectory: ObjCBool = false
                guard fm.fileExists(atPath: path, isDirectory: &isDirectory),
                      isDirectory.boolValue else { return nil }
                return path
            }
            .sorted()
    }

    /// Finds direct session transcripts and nested `<session>/subagents/*.jsonl` files.
    nonisolated static func files(inProjectDirectory projectDirectory: String) -> [String] {
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(atPath: projectDirectory) else { return [] }

        var result = entries
            .filter { $0.hasSuffix(".jsonl") }
            .map { projectDirectory + "/" + $0 }

        for entry in entries {
            let subagentsDirectory = projectDirectory + "/" + entry + "/subagents"
            var isDirectory: ObjCBool = false
            guard fm.fileExists(atPath: subagentsDirectory, isDirectory: &isDirectory),
                  isDirectory.boolValue,
                  let subagentFiles = try? fm.contentsOfDirectory(atPath: subagentsDirectory)
            else { continue }

            result.append(contentsOf: subagentFiles
                .filter { $0.hasSuffix(".jsonl") }
                .map { subagentsDirectory + "/" + $0 })
        }

        return result.sorted()
    }

    /// Finds transcripts below one or more `projects` roots, optionally filtered by mtime.
    nonisolated static func files(
        inProjectsDirectories projectsDirectories: [String],
        modifiedSince: Date? = nil
    ) -> [String] {
        let fm = FileManager.default
        var result: [String] = []

        for projectsDirectory in projectsDirectories {
            guard let projects = try? fm.contentsOfDirectory(atPath: projectsDirectory) else { continue }
            for project in projects {
                let projectDirectory = projectsDirectory + "/" + project
                for path in files(inProjectDirectory: projectDirectory) {
                    if let modifiedSince {
                        guard let attributes = try? fm.attributesOfItem(atPath: path),
                              let modificationDate = attributes[.modificationDate] as? Date,
                              modificationDate >= modifiedSince else { continue }
                    }
                    result.append(path)
                }
            }
        }

        return result.sorted()
    }
}
