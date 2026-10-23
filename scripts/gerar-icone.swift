#!/usr/bin/env swift
// Desenha o ícone do HollyCorretor e grava Resources/AppIcon.icns.
//
// O ícone é feito em código, e não num arquivo de imagem, para a identidade
// poder ser ajustada e regerada por quem compila com as Command Line Tools,
// sem Xcode nem editor gráfico: uma folha de texto sobre o fundo escuro da
// suíte Holly, com o selo de conferência no laranja da marca — o mesmo do
// banner do README.
//
// Uso: swift scripts/gerar-icone.swift [caminho/do/AppIcon.icns]

import AppKit

let output = CommandLine.arguments.count > 1
    ? URL(fileURLWithPath: CommandLine.arguments[1])
    : URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        .appendingPathComponent("Resources/AppIcon.icns")

/// Desenha o ícone num quadrado de lado `side`, em pontos, no contexto atual.
func draw(side: CGFloat) {
    let s = side / 1024
    let canvas = NSRect(x: 0, y: 0, width: side, height: side)

    // Fundo: o quadrado arredondado padrão do macOS ocupa ~82% do quadro,
    // com raio contínuo de ~22% do lado.
    let inset = 100 * s
    let plate = canvas.insetBy(dx: inset, dy: inset)
    let plateRadius = plate.width * 0.2237
    let platePath = NSBezierPath(roundedRect: plate, xRadius: plateRadius, yRadius: plateRadius)

    NSGraphicsContext.saveGraphicsState()
    let plateShadow = NSShadow()
    plateShadow.shadowColor = NSColor.black.withAlphaComponent(0.35)
    plateShadow.shadowBlurRadius = 24 * s
    plateShadow.shadowOffset = NSSize(width: 0, height: -12 * s)
    plateShadow.set()
    NSColor(srgbRed: 0.05, green: 0.08, blue: 0.13, alpha: 1).setFill()
    platePath.fill()
    NSGraphicsContext.restoreGraphicsState()

    NSGraphicsContext.saveGraphicsState()
    platePath.addClip()
    let background = NSGradient(colors: [
        NSColor(srgbRed: 0.11, green: 0.17, blue: 0.26, alpha: 1),
        NSColor(srgbRed: 0.03, green: 0.06, blue: 0.10, alpha: 1)
    ])!
    background.draw(in: plate, angle: -90)

    // Brilho quente e difuso vindo do canto inferior direito, onde fica o selo.
    let glow = NSGradient(colorsAndLocations:
        (NSColor(srgbRed: 1.0, green: 0.60, blue: 0.36, alpha: 0.28), 0),
        (NSColor(srgbRed: 1.0, green: 0.60, blue: 0.36, alpha: 0.0), 1)
    )!
    glow.draw(
        fromCenter: NSPoint(x: plate.maxX - plate.width * 0.22, y: plate.minY + plate.height * 0.20),
        radius: 0,
        toCenter: NSPoint(x: plate.maxX - plate.width * 0.22, y: plate.minY + plate.height * 0.20),
        radius: plate.width * 0.75,
        options: []
    )

    // Linhas finas de circuito, como no banner, bem discretas.
    NSColor(srgbRed: 0.71, green: 0.65, blue: 0.54, alpha: 0.16).setStroke()
    let trace = NSBezierPath()
    trace.lineWidth = 6 * s
    trace.lineCapStyle = .round
    trace.move(to: NSPoint(x: plate.minX + 40 * s, y: plate.maxY - 140 * s))
    trace.line(to: NSPoint(x: plate.minX + 150 * s, y: plate.maxY - 140 * s))
    trace.line(to: NSPoint(x: plate.minX + 200 * s, y: plate.maxY - 190 * s))
    trace.move(to: NSPoint(x: plate.maxX - 40 * s, y: plate.minY + 170 * s))
    trace.line(to: NSPoint(x: plate.maxX - 130 * s, y: plate.minY + 170 * s))
    trace.line(to: NSPoint(x: plate.maxX - 180 * s, y: plate.minY + 220 * s))
    trace.stroke()
    NSGraphicsContext.restoreGraphicsState()

    // Folha: um cartão claro, levemente deslocado para a esquerda e para cima
    // para deixar lugar ao selo.
    let sheet = NSRect(
        x: plate.minX + plate.width * 0.22,
        y: plate.minY + plate.height * 0.22,
        width: plate.width * 0.50,
        height: plate.height * 0.60
    )
    let sheetPath = NSBezierPath(roundedRect: sheet, xRadius: 44 * s, yRadius: 44 * s)
    NSGraphicsContext.saveGraphicsState()
    let sheetShadow = NSShadow()
    sheetShadow.shadowColor = NSColor.black.withAlphaComponent(0.45)
    sheetShadow.shadowBlurRadius = 30 * s
    sheetShadow.shadowOffset = NSSize(width: 0, height: -14 * s)
    sheetShadow.set()
    NSColor(srgbRed: 1.0, green: 0.97, blue: 0.93, alpha: 1).setFill()
    sheetPath.fill()
    NSGraphicsContext.restoreGraphicsState()

    NSGraphicsContext.saveGraphicsState()
    sheetPath.addClip()
    NSGradient(colors: [
        NSColor(srgbRed: 1.0, green: 0.98, blue: 0.95, alpha: 1),
        NSColor(srgbRed: 0.96, green: 0.92, blue: 0.86, alpha: 1)
    ])!.draw(in: sheet, angle: -90)
    NSGraphicsContext.restoreGraphicsState()

    // Linhas de texto na folha: a primeira mais curta, como um título.
    let ink = NSColor(srgbRed: 0.16, green: 0.20, blue: 0.27, alpha: 1)
    let lineHeight = 34 * s
    let lineGap = 74 * s
    let lineLeft = sheet.minX + 64 * s
    var lineTop = sheet.maxY - 86 * s
    let widths: [CGFloat] = [0.42, 0.72, 0.72, 0.58]
    for (index, fraction) in widths.enumerated() {
        let width = (sheet.width - 128 * s) * fraction
        let line = NSRect(x: lineLeft, y: lineTop - lineHeight, width: width, height: lineHeight)
        (index == 0 ? ink : ink.withAlphaComponent(0.55)).setFill()
        NSBezierPath(roundedRect: line, xRadius: lineHeight / 2, yRadius: lineHeight / 2).fill()
        lineTop -= lineGap
    }

    // Selo de conferência: círculo no gradiente laranja→dourado da marca, com
    // o sinal de certo em branco, encavalado no canto inferior direito da folha.
    let badgeDiameter = plate.width * 0.36
    let badge = NSRect(
        x: sheet.maxX - badgeDiameter * 0.58,
        y: sheet.minY - badgeDiameter * 0.18,
        width: badgeDiameter,
        height: badgeDiameter
    )
    let badgePath = NSBezierPath(ovalIn: badge)
    NSGraphicsContext.saveGraphicsState()
    let badgeShadow = NSShadow()
    badgeShadow.shadowColor = NSColor.black.withAlphaComponent(0.40)
    badgeShadow.shadowBlurRadius = 26 * s
    badgeShadow.shadowOffset = NSSize(width: 0, height: -10 * s)
    badgeShadow.set()
    NSColor(srgbRed: 1.0, green: 0.60, blue: 0.36, alpha: 1).setFill()
    badgePath.fill()
    NSGraphicsContext.restoreGraphicsState()

    NSGraphicsContext.saveGraphicsState()
    badgePath.addClip()
    NSGradient(colors: [
        NSColor(srgbRed: 1.00, green: 0.60, blue: 0.36, alpha: 1),
        NSColor(srgbRed: 0.95, green: 0.78, blue: 0.40, alpha: 1)
    ])!.draw(in: badge, angle: 45)
    NSGraphicsContext.restoreGraphicsState()

    // Anel claro fino na borda do selo, para destacá-lo da folha.
    NSColor.white.withAlphaComponent(0.55).setStroke()
    let ring = NSBezierPath(ovalIn: badge.insetBy(dx: 7 * s, dy: 7 * s))
    ring.lineWidth = 10 * s
    ring.stroke()

    let check = NSBezierPath()
    check.lineWidth = badgeDiameter * 0.13
    check.lineCapStyle = .round
    check.lineJoinStyle = .round
    check.move(to: NSPoint(x: badge.minX + badge.width * 0.28, y: badge.midY - badge.height * 0.02))
    check.line(to: NSPoint(x: badge.minX + badge.width * 0.44, y: badge.midY - badge.height * 0.18))
    check.line(to: NSPoint(x: badge.minX + badge.width * 0.74, y: badge.midY + badge.height * 0.18))
    NSColor.white.setStroke()
    check.stroke()
}

func render(pixels: Int) -> Data {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: pixels,
        pixelsHigh: pixels,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .calibratedRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    )!
    rep.size = NSSize(width: pixels, height: pixels)
    NSGraphicsContext.saveGraphicsState()
    let context = NSGraphicsContext(bitmapImageRep: rep)!
    NSGraphicsContext.current = context
    context.cgContext.setAllowsAntialiasing(true)
    context.cgContext.interpolationQuality = .high
    draw(side: CGFloat(pixels))
    context.flushGraphics()
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

let fileManager = FileManager.default
let staging = fileManager.temporaryDirectory
    .appendingPathComponent("HollyCorretor-\(ProcessInfo.processInfo.processIdentifier)")
let iconset = staging.appendingPathComponent("AppIcon.iconset")
try fileManager.createDirectory(at: iconset, withIntermediateDirectories: true)
defer { try? fileManager.removeItem(at: staging) }

// Os pares exigidos pelo iconutil: cada tamanho em 1x e 2x.
for points in [16, 32, 128, 256, 512] {
    try render(pixels: points).write(to: iconset.appendingPathComponent("icon_\(points)x\(points).png"))
    try render(pixels: points * 2).write(to: iconset.appendingPathComponent("icon_\(points)x\(points)@2x.png"))
}

try fileManager.createDirectory(
    at: output.deletingLastPathComponent(), withIntermediateDirectories: true
)
let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", iconset.path, "-o", output.path]
try iconutil.run()
iconutil.waitUntilExit()
guard iconutil.terminationStatus == 0 else {
    FileHandle.standardError.write(Data("iconutil falhou (\(iconutil.terminationStatus)).\n".utf8))
    exit(1)
}
print(output.path)
