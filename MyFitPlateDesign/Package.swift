// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "MyFitPlateDesign",
    platforms: [.iOS(.v15)],
    products: [.library(name: "MyFitPlateDesign", targets: ["MyFitPlateDesign"])],
    targets: [.target(name: "MyFitPlateDesign", resources: [.process("Resources")])]
)
