import Foundation

@main
enum ValidateGolfDataset {
    static func main() throws {
        guard CommandLine.arguments.count == 2 else {
            FileHandle.standardError.write(
                Data("usage: validate-golf-dataset <dataset-root>\n".utf8)
            )
            Foundation.exit(64)
        }

        let snapshot = try GolfDatasetStore(
            rootDirectory: URL(
                fileURLWithPath: CommandLine.arguments[1],
                isDirectory: true
            )
        ).loadSnapshot()
        let errors = GolfDatasetValidator.validate(snapshot: snapshot)
        guard errors.isEmpty else {
            for error in errors {
                print(error.description)
            }
            Foundation.exit(1)
        }
        print("dataset contract passed")
    }
}
