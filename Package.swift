// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Pynkaro",
    platforms: [
        .macOS("13.1") // exigido pelo runtime da Rive
    ],
    dependencies: [
        // Rig 2D animado do avatar (arquivo avatar.riv na raiz do projeto).
        .package(url: "https://github.com/rive-app/rive-ios", from: "6.0.0")
    ],
    targets: [
        // Núcleo testável: toda a lógica (máquina de estados, LLM, TTS,
        // config, serviços). O alvo de testes importa só esta biblioteca.
        .target(
            name: "PynkaroCore",
            dependencies: [
                .product(name: "RiveRuntime", package: "rive-ios")
            ],
            path: "Sources/PynkaroCore"
        ),
        // Executável fino: entrada do app (menu bar). Sem lógica de negócio.
        .executableTarget(
            name: "Pynkaro",
            dependencies: ["PynkaroCore"],
            path: "Sources/Pynkaro"
        ),
        .testTarget(
            name: "PynkaroTests",
            dependencies: ["PynkaroCore"],
            path: "Tests/PynkaroTests"
        )
    ]
)
