import Foundation

let source = try String(
    contentsOfFile: "SwingArc/Views/BrandMarkView.swift",
    encoding: .utf8
)

precondition(source.contains("struct BrandMarkView"))
precondition(source.contains("struct SwingArcRibbonShape"))
precondition(source.contains("accessibilityLabel(\"SwingArc\")"))
precondition(!source.contains("figure.golf"))

print("Brand mark source smoke passed")
