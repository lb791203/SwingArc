import Foundation

@main
struct ValidateAnnotationExport {
    static func main() throws {
        guard CommandLine.arguments.count == 2 else {
            fputs(
                "usage: validate-annotation-export <json-path>\n",
                stderr
            )
            exit(EXIT_FAILURE)
        }
        let url = URL(fileURLWithPath: CommandLine.arguments[1])
        let package = try AnnotationCoding.makeDecoder().decode(
            AnnotationPackage.self,
            from: Data(contentsOf: url)
        )
        let errors = AnnotationPackageValidator.validate(package)
        guard package.frozenAt != nil, errors.isEmpty else {
            for error in errors {
                fputs("\(error)\n", stderr)
            }
            exit(EXIT_FAILURE)
        }
        print(
            "VALID \(package.metadata.clipID) " +
                "\(package.media.frameCount) frames " +
                "\(package.passes.count) passes"
        )
    }
}
