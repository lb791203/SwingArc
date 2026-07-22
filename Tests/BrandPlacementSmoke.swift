import Foundation

func source(_ path: String) throws -> String {
    try String(contentsOfFile: path, encoding: .utf8)
}

let home = try source("SwingArc/Views/PracticeHomeView.swift")
let library = try source("SwingArc/Views/ProjectLibraryView.swift")
let app = try source("SwingArc/SwingArcApp.swift")

precondition(home.contains("BrandMarkView(size: 30"))
precondition(library.contains("BrandMarkView(size: 60"))
precondition(library.contains("BrandMarkView(size: 20"))
precondition(app.contains("BrandLaunchView"))
precondition(!home.contains("Image(systemName: \"figure.golf\")\n                    .font(.system(size: 17"))

print("Brand placement smoke passed")
