import SwiftUI

private enum BombLaunchTiming {
    static let ignition = 0.25
    static let fuseDuration = 3.4
    static let explosion = ignition + fuseDuration
    static let blastDuration = 1.05
    static let reveal = explosion + blastDuration
}

/// Replays the entrance without rebuilding the underlying login, navigation or stores.
struct BombLaunchView<Content: View>: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @State private var startedAt = ContinuousClock.now
    @State private var playbackGeneration = UUID()
    @State private var isRevealed = false
    @State private var isFinished = false
    @State private var playingReplayID: Int?
    let playsAnimation: Bool
    let replayID: Int
    let coversWhenInactive: Bool
    @ViewBuilder let content: () -> Content

    init(playsAnimation: Bool = true, replayID: Int = 0, coversWhenInactive: Bool = false,
         @ViewBuilder content: @escaping () -> Content) {
        self.playsAnimation = playsAnimation
        self.replayID = replayID
        self.coversWhenInactive = coversWhenInactive
        self.content = content
        _isRevealed = State(initialValue: !playsAnimation)
        _isFinished = State(initialValue: !playsAnimation)
    }

    var body: some View {
        // A new request covers content immediately; .task starts on a later render pass.
        let holdsFirstFrame = playsAnimation && (playingReplayID != replayID
            || (coversWhenInactive && scenePhase != .active))
        let revealed = isRevealed && !holdsFirstFrame
        ZStack {
            content()
                .opacity(revealed ? 1 : 0)
                .allowsHitTesting(revealed)
                .accessibilityHidden(!revealed)

            if !isFinished || holdsFirstFrame {
                GeometryReader { proxy in
                    TimelineView(.animation(paused: reduceMotion || scenePhase != .active)) { _ in
                        let duration = startedAt.duration(to: .now).components
                        let elapsed = Double(duration.seconds) + Double(duration.attoseconds) / 1e18
                        BombLaunchArtwork(elapsed: reduceMotion || holdsFirstFrame ? 0 : max(0, elapsed))
                    }
                    .background(BombTheme.yellow)
                    .offset(x: reduceMotion ? 0 : (revealed ? -proxy.size.width * 1.15 : 0))
                    .opacity(reduceMotion && revealed ? 0 : 1)
                }
                .ignoresSafeArea()
                .allowsHitTesting(false)
                .accessibilityHidden(true)

                if !revealed {
                    VStack {
                        HStack {
                            Spacer()
                            Button(L10n.text("略過動畫")) { reveal() }
                                .disabled(scenePhase != .active)
                                .font(.caption.weight(.bold))
                                .foregroundStyle(BombTheme.ink)
                                .padding(.horizontal, 16)
                                .frame(minHeight: 44)
                                .background(BombTheme.paper, in: Capsule())
                                .buttonStyle(.plain)
                        }
                        Spacer()
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
                }
            }
        }
        .background(BombTheme.yellow)
        .task(id: PlaybackRequest(replayID: replayID, isActive: scenePhase == .active)) {
            guard playsAnimation, scenePhase == .active,
                  playingReplayID != replayID || !isFinished else { return }
            let generation = UUID()
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                playbackGeneration = generation
                playingReplayID = replayID
                startedAt = .now
                isRevealed = false
                isFinished = false
            }
            do {
                try await Task.sleep(for: .seconds(reduceMotion ? 0.2 : BombLaunchTiming.reveal))
                guard !Task.isCancelled, playbackGeneration == generation else { return }
                reveal()
            } catch { }
        }
        .task(id: isRevealed) {
            guard isRevealed else { return }
            let generation = playbackGeneration
            do {
                try await Task.sleep(for: .seconds(reduceMotion ? 0.2 : 0.75))
                guard !Task.isCancelled, playbackGeneration == generation, isRevealed else { return }
                isFinished = true
            } catch { }
        }
        .onChange(of: reduceMotion) { _, enabled in
            if enabled { reveal() }
        }
    }

    private struct PlaybackRequest: Equatable {
        let replayID: Int
        let isActive: Bool
    }

    private func reveal() {
        guard !isRevealed else { return }
        withAnimation(reduceMotion ? .easeOut(duration: 0.18) : .timingCurve(0.76, 0, 0.18, 1, duration: 0.7)) {
            isRevealed = true
        }
    }
}

/// Restrained screen-print artwork using the existing ink, paper and yellow palette.
private struct BombLaunchArtwork: View {
    let elapsed: TimeInterval

    var body: some View {
        Canvas { context, size in
            guard size.width.isFinite, size.height.isFinite,
                  size.width > 0, size.height > 0 else { return }
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(BombTheme.yellow))
            let unit = min(size.width / 390, size.height / 780)
            let center = CGPoint(x: size.width / 2, y: size.height * 0.43)
            drawHalftone(context: context, size: size, unit: unit)

            if elapsed < BombLaunchTiming.explosion {
                let burn = min(1, max(0, (elapsed - BombLaunchTiming.ignition) / BombLaunchTiming.fuseDuration))
                var scene = context
                scene.translateBy(x: center.x, y: center.y)
                scene.scaleBy(x: unit, y: unit)
                drawGroundShadow(context: scene)

                var bomb = scene
                bomb.concatenate(bombTransform(at: elapsed))
                drawBomb(context: bomb)
                drawFuse(context: bomb, burn: burn)
                drawSparks(context: scene, burn: burn)

                let title = Text("OOPS BOMB")
                    .font(.custom("AvenirNextCondensed-Heavy", fixedSize: 42 * unit))
                    .tracking(0.7 * unit)
                context.draw(title.foregroundStyle(BombTheme.paper),
                             at: CGPoint(x: center.x + 1.5 * unit, y: center.y + 182.5 * unit))
                context.draw(title.foregroundStyle(BombTheme.ink),
                             at: CGPoint(x: center.x, y: center.y + 180 * unit))
                context.draw(Text("雷包點點名").font(.system(size: 14 * unit, weight: .black, design: .rounded))
                    .tracking(3 * unit).foregroundStyle(BombTheme.ink),
                    at: CGPoint(x: center.x, y: center.y + 236 * unit))
            } else {
                drawExplosion(context: context, center: center, size: size, unit: unit)
            }
        }
    }

    private func bombTransform(at time: TimeInterval) -> CGAffineTransform {
        let burning = max(0, time - BombLaunchTiming.ignition)
        let burn = min(1, burning / BombLaunchTiming.fuseDuration)
        let pressure = pow(burn, 1.8)
        let onset = min(1, burning / 0.3)
        let attack = onset * onset * (3 - 2 * onset)
        // Continuous overlapping vibrations avoid a pendulum rhythm or frame-by-frame jitter.
        // Most movement is translation; the shell barely tilts around its own center.
        let phase = 2 * Double.pi * (4.2 * burning + 0.85 * burning * burning / BombLaunchTiming.fuseDuration)
        let amplitude = (0.18 + pressure * 6) * attack
        let x = (sin(phase) * 0.7 + sin(phase * 1.41) * 0.22 + sin(phase * 1.91) * 0.08) * amplitude
        let y = (sin(phase * 0.91) * 0.64 + sin(phase * 1.27) * 0.36) * amplitude * 0.3
        let angle = (sin(phase * 0.78) * 0.6 + sin(phase * 1.23) * 0.4) * pressure * 0.95 * .pi / 180
        let finalBurn = max(0, (burn - 0.72) / 0.28)
        let strain = finalBurn * finalBurn * (3 - 2 * finalBurn)
        let dilation = 1 + pressure * 0.013 + strain * (0.003 + 0.003 * sin(burning * 18))
        return CGAffineTransform(translationX: x, y: y + 23)
            .rotated(by: angle)
            .scaledBy(x: dilation, y: dilation)
            .translatedBy(x: 0, y: -23)
    }

    private func drawHalftone(context: GraphicsContext, size: CGSize, unit: CGFloat) {
        let spacing = 12 * unit
        for row in 0...Int(size.height / spacing) {
            for column in 0...Int(size.width / spacing) {
                let x = CGFloat(column) * spacing
                let y = CGFloat(row) * spacing
                // Printed dot fields in opposite corners, with an open center.
                let corner = max(0, 1 - hypot(x - size.width, y - size.height * 0.16) / (size.width * 0.62))
                    + max(0, 1 - hypot(x, y - size.height * 0.88) / (size.width * 0.65))
                guard corner > 0 else { continue }
                let radius = (0.5 + corner * 1.4) * unit
                context.fill(Path(ellipseIn: CGRect(x: x, y: y, width: radius * 2, height: radius * 2)),
                    with: .color(BombTheme.ink.opacity(0.16)))
            }
        }
    }

    private func drawGroundShadow(context: GraphicsContext) {
        // Separate contact and ambient shadows ground the object without a hard flat oval.
        var ground = context
        ground.addFilter(.blur(radius: 5))
        ground.fill(Path(ellipseIn: CGRect(x: -69, y: 122, width: 143, height: 14)),
                    with: .color(BombTheme.ink.opacity(0.18)))
        context.fill(Path(ellipseIn: CGRect(x: -39, y: 126, width: 83, height: 4)),
                     with: .color(BombTheme.ink.opacity(0.1)))
    }

    private func drawBomb(context: GraphicsContext) {
        let body = Path(ellipseIn: CGRect(x: -90, y: -67, width: 180, height: 180))
        let bronze = Color(red: 0.48, green: 0.31, blue: 0.09)
        let charcoal = Color(red: 0.035, green: 0.043, blue: 0.039)

        // A machined brass collar catches the same upper-left light as the enamel shell.
        var cap = context
        cap.translateBy(x: 27, y: -65)
        cap.rotate(by: .degrees(18))
        let collar = Path(roundedRect: CGRect(x: -18, y: -22, width: 36, height: 30), cornerRadius: 6)
        cap.fill(collar, with: .linearGradient(Gradient(stops: [
            .init(color: bronze, location: 0),
            .init(color: BombTheme.paper, location: 0.25),
            .init(color: BombTheme.yellow, location: 0.52),
            .init(color: bronze, location: 1)
        ]), startPoint: CGPoint(x: -18, y: 0), endPoint: CGPoint(x: 18, y: 0)))
        cap.stroke(collar, with: .color(BombTheme.ink), lineWidth: 3)
        for x in stride(from: -10.0, through: 10.0, by: 10) {
            var seam = Path()
            seam.move(to: CGPoint(x: x, y: -16))
            seam.addLine(to: CGPoint(x: x, y: 1))
            cap.stroke(seam, with: .color(BombTheme.ink.opacity(0.5)), style: StrokeStyle(lineWidth: 2, lineCap: .round))
            var edge = cap
            edge.translateBy(x: -1, y: 0)
            edge.stroke(seam, with: .color(BombTheme.paper.opacity(0.5)), lineWidth: 0.7)
        }
        let socket = Path(ellipseIn: CGRect(x: -14, y: -24, width: 28, height: 7))
        cap.fill(socket, with: .color(BombTheme.ink))
        cap.stroke(socket, with: .color(BombTheme.paper.opacity(0.65)), lineWidth: 1)

        // Off-center radial light describes a sphere, with a deep shaded lower-right edge.
        context.fill(body, with: .radialGradient(Gradient(stops: [
            .init(color: Color(red: 0.48, green: 0.49, blue: 0.43), location: 0),
            .init(color: Color(red: 0.30, green: 0.32, blue: 0.28), location: 0.23),
            .init(color: Color(red: 0.13, green: 0.15, blue: 0.13), location: 0.55),
            .init(color: charcoal, location: 0.84),
            .init(color: .black, location: 1)
        ]), center: CGPoint(x: -37, y: -25), startRadius: 0, endRadius: 160))
        context.stroke(body, with: .color(BombTheme.ink), lineWidth: 2)

        var shell = context
        shell.clip(to: body)
        shell.fill(body, with: .radialGradient(Gradient(colors: [BombTheme.yellow.opacity(0.28), .clear]),
            center: CGPoint(x: 76, y: 83), startRadius: 0, endRadius: 104))

        // Broad satin reflection, followed by a narrow edge highlight; no white sticker shine.
        var reflection = Path()
        reflection.move(to: CGPoint(x: -68, y: 5))
        reflection.addCurve(to: CGPoint(x: 10, y: -52), control1: CGPoint(x: -70, y: -34), control2: CGPoint(x: -20, y: -66))
        reflection.addCurve(to: CGPoint(x: -57, y: 8), control1: CGPoint(x: -24, y: -47), control2: CGPoint(x: -51, y: -25))
        reflection.closeSubpath()
        var softLight = shell
        softLight.addFilter(.blur(radius: 4))
        softLight.fill(reflection, with: .color(BombTheme.paper.opacity(0.22)))

        for row in 0..<19 {
            for column in 0..<19 {
                let x = -90 + CGFloat(column) * 10
                let y = -65 + CGFloat(row) * 10
                let shade = max(0, min(1, (x + y + 45) / 220))
                shell.fill(Path(ellipseIn: CGRect(x: x, y: y, width: 0.6 + shade, height: 0.6 + shade)),
                           with: .color(BombTheme.paper.opacity(0.035 + shade * 0.045)))
            }
        }

        var rim = Path()
        rim.addArc(center: CGPoint(x: 0, y: 23), radius: 85,
            startAngle: .degrees(8), endAngle: .degrees(92), clockwise: false)
        context.stroke(rim, with: .linearGradient(Gradient(colors: [BombTheme.yellow.opacity(0.1), BombTheme.yellow.opacity(0.65), .clear]),
            startPoint: CGPoint(x: 83, y: 15), endPoint: CGPoint(x: 0, y: 110)),
            style: StrokeStyle(lineWidth: 2, lineCap: .round))

        var highlight = Path()
        highlight.addArc(center: CGPoint(x: 0, y: 23), radius: 84,
            startAngle: .degrees(192), endAngle: .degrees(267), clockwise: false)
        context.stroke(highlight, with: .linearGradient(Gradient(colors: [BombTheme.paper.opacity(0.12), BombTheme.paper.opacity(0.85), BombTheme.paper.opacity(0.15)]),
            startPoint: CGPoint(x: -85, y: 15), endPoint: CGPoint(x: 5, y: -62)),
            style: StrokeStyle(lineWidth: 2, lineCap: .round))

        var bolt = Path()
        bolt.move(to: CGPoint(x: 16, y: -28))
        for point in [CGPoint(x: -29, y: 29), CGPoint(x: -4, y: 29), CGPoint(x: -15, y: 76),
                      CGPoint(x: 38, y: 10), CGPoint(x: 10, y: 10)] {
            bolt.addLine(to: point)
        }
        bolt.closeSubpath()
        var boltShadow = context
        boltShadow.translateBy(x: 4, y: 6)
        boltShadow.addFilter(.blur(radius: 2.5))
        boltShadow.fill(bolt, with: .color(.black.opacity(0.6)))
        // A shallow bronze extrusion makes the lightning feel inset into a real emblem.
        for depth in stride(from: 3.0, through: 1.0, by: -1) {
            var bevel = context
            bevel.translateBy(x: depth * 0.6, y: depth)
            bevel.fill(bolt, with: .color(bronze))
        }
        context.fill(bolt, with: .linearGradient(Gradient(stops: [
            .init(color: BombTheme.paper, location: 0),
            .init(color: BombTheme.yellow, location: 0.34),
            .init(color: BombTheme.yellow, location: 0.7),
            .init(color: Color(red: 0.85, green: 0.55, blue: 0.04), location: 1)
        ]), startPoint: CGPoint(x: -18, y: -28), endPoint: CGPoint(x: 25, y: 80)))
        context.stroke(bolt, with: .color(BombTheme.yellow.opacity(0.55)), lineWidth: 0.7)
        var bevelLight = Path()
        bevelLight.move(to: CGPoint(x: 16, y: -28))
        bevelLight.addLine(to: CGPoint(x: -29, y: 29))
        bevelLight.addLine(to: CGPoint(x: -4, y: 29))
        context.stroke(bevelLight, with: .color(BombTheme.paper.opacity(0.65)),
                       style: StrokeStyle(lineWidth: 1, lineCap: .round, lineJoin: .round))
    }

    private func fusePoint(_ fraction: Double) -> CGPoint {
        // The ember and remaining fuse use the same curve, so they never separate.
        let x = 25 + 97 * fraction
        let y = -82 - 57 * fraction - 22 * sin(fraction * .pi * 2)
        return CGPoint(x: x, y: y)
    }

    private func drawFuse(context: GraphicsContext, burn: Double) {
        let remaining = 1 - burn
        var fuse = Path()
        fuse.move(to: fusePoint(0))
        for index in 1...80 { fuse.addLine(to: fusePoint(remaining * Double(index) / 80)) }
        context.stroke(fuse, with: .color(BombTheme.ink), style: StrokeStyle(lineWidth: 8, lineCap: .round))
        context.stroke(fuse, with: .color(BombTheme.paper), style: StrokeStyle(lineWidth: 4, lineCap: .round))
        for index in 0..<20 {
            let fraction = Double(index) / 20
            guard fraction < remaining else { break }
            let point = fusePoint(fraction)
            var braid = Path()
            braid.move(to: CGPoint(x: point.x - 2, y: point.y - 2))
            braid.addLine(to: CGPoint(x: point.x + 2, y: point.y + 2))
            context.stroke(braid, with: .color(BombTheme.ink), lineWidth: 1.3)
        }
    }

    private func drawSparks(context: GraphicsContext, burn: Double) {
        let ember = fusePoint(1 - burn).applying(bombTransform(at: elapsed))
        let burnTime = max(0, elapsed - BombLaunchTiming.ignition)
        let heat = pow(burn, 1.45)
        let orange = Color(red: 1, green: 0.49, blue: 0.08)
        let copper = Color(red: 0.52, green: 0.18, blue: 0.035)
        let hotCore = Color(red: 1, green: 0.97, blue: 0.81)

        // Embers leave the moving fuse in world space, so airborne trails don't shake
        // with the shell. Each flight gets a new direction and a smooth opacity envelope.
        for index in 0..<64 {
            let seed = Double(index)
            let lifetime = 0.28 + Double(index % 7) * 0.035
            let cycle = burnTime / lifetime + seed * 0.61803398875
            let flight = floor(cycle)
            let age = (cycle - flight) * lifetime
            let birthTime = burnTime - age
            guard birthTime >= 0 else { continue }
            let birthBurn = min(1, birthTime / BombLaunchTiming.fuseDuration)
            let birthHeat = pow(birthBurn, 1.45)
            let finalBurn = max(0, (birthBurn - 0.72) / 0.28)
            let surge = finalBurn * finalBurn * (3 - 2 * finalBurn)
            let visibility = min(1, max(0, 8 + birthHeat * 40 + surge * 16 - seed))
            guard visibility > 0 else { continue }
            let origin = fusePoint(1 - birthBurn)
                .applying(bombTransform(at: BombLaunchTiming.ignition + birthTime))
            let spread = (seed * 0.38196601125 + flight * 0.17320508076).truncatingRemainder(dividingBy: 1)
            let angle = index.isMultiple(of: 5) ? spread * .pi * 2 : -.pi * 0.96 + spread * .pi * 0.92
            let speed = (85 + birthHeat * 155 + surge * 40) * (0.65 + Double(index % 5) * 0.12)
            let velocityX = cos(angle) * speed
            let velocityY = sin(angle) * speed
            let trailDuration = index.isMultiple(of: 4) ? 0.024 + birthHeat * 0.03 : 0.012 + birthHeat * 0.012
            let tailAge = max(0, age - trailDuration)
            let head = CGPoint(x: origin.x + velocityX * age, y: origin.y + velocityY * age + 105 * age * age)
            let tail = CGPoint(x: origin.x + velocityX * tailAge, y: origin.y + velocityY * tailAge + 105 * tailAge * tailAge)
            let warming = min(1, age / 0.04)
            let cooling = min(1, max(0, (age / lifetime - 0.45) / 0.55))
            let fade = visibility * warming * warming * (3 - 2 * warming)
                * (1 - cooling * cooling * (3 - 2 * cooling))
            var trail = Path()
            trail.move(to: tail)
            let control = CGPoint(x: tail.x + velocityX * (age - tailAge) / 2,
                                  y: tail.y + (velocityY + 210 * tailAge) * (age - tailAge) / 2)
            trail.addQuadCurve(to: head, control: control)
            context.stroke(trail, with: .linearGradient(Gradient(colors: [copper.opacity(fade * 0.12), copper.opacity(fade * 0.85)]),
                                                        startPoint: tail, endPoint: head),
                           style: StrokeStyle(lineWidth: 2.8, lineCap: .round))
            context.stroke(trail, with: .linearGradient(Gradient(colors: [orange.opacity(fade * 0.15), hotCore.opacity(fade)]),
                                                        startPoint: tail, endPoint: head),
                           style: StrokeStyle(lineWidth: 1.25, lineCap: .round))
            let core = 0.65 + birthHeat * 0.45
            context.fill(Path(ellipseIn: CGRect(x: head.x - core, y: head.y - core, width: core * 2, height: core * 2)),
                         with: .color(hotCore.opacity(fade)))
        }

        var spark = context
        spark.translateBy(x: ember.x, y: ember.y)
        let radius = 13 + heat * 11 + sin(elapsed * 17) + 0.5 * sin(elapsed * 27)
        spark.fill(Path(ellipseIn: CGRect(x: -radius, y: -radius, width: radius * 2, height: radius * 2)),
                   with: .radialGradient(Gradient(colors: [orange.opacity(0.48), orange.opacity(0)]),
                                         center: .zero, startRadius: 2, endRadius: radius))
        let coreRadius = 4 + heat * 2
        spark.fill(Path(ellipseIn: CGRect(x: -coreRadius, y: -coreRadius, width: coreRadius * 2, height: coreRadius * 2)),
                   with: .color(orange))
        spark.fill(Path(ellipseIn: CGRect(x: -2.2, y: -2.2, width: 4.4, height: 4.4)), with: .color(hotCore))
    }

    private func drawExplosion(context: GraphicsContext, center: CGPoint, size: CGSize, unit: CGFloat) {
        let progress = min(1, (elapsed - BombLaunchTiming.explosion) / BombLaunchTiming.blastDuration)
        let expansion = 1 - pow(1 - progress, 2.4)
        var explosion = context
        let shake = pow(1 - progress, 3) * 9 * unit
        explosion.translateBy(x: center.x + sin(progress * 65) * shake,
                              y: center.y + cos(progress * 53) * shake * 0.6)
        let radius = 30 * unit + expansion * hypot(size.width, size.height)

        // An ink front hits first, followed by paper: one impact, without repeated flashes.
        let frontRadius = radius * 1.19
        let front = Path(ellipseIn: CGRect(x: -frontRadius, y: -frontRadius, width: frontRadius * 2, height: frontRadius * 2))
        explosion.fill(front, with: .color(BombTheme.ink))
        explosion.stroke(front, with: .color(BombTheme.paper.opacity(0.8)), lineWidth: 4 * unit)
        let wave = Path(ellipseIn: CGRect(x: -radius, y: -radius, width: radius * 2, height: radius * 2))
        explosion.fill(wave, with: .color(BombTheme.paper))
        explosion.stroke(wave, with: .color(BombTheme.yellow), lineWidth: (4 + 12 * (1 - progress)) * unit)
        let echoRadius = radius * 0.81
        let echo = Path(ellipseIn: CGRect(x: -echoRadius, y: -echoRadius, width: echoRadius * 2, height: echoRadius * 2))
        explosion.stroke(echo, with: .color(BombTheme.ink.opacity((1 - progress) * 0.5)), lineWidth: 2 * unit)

        // Streak lengths grow with speed instead of forming a static comic outline.
        for index in 0..<28 {
            let angle = Double(index) * .pi / 14 + 0.11
            let near = radius * (0.3 + Double(index % 4) * 0.04)
            let far = radius * (0.69 + Double(index % 3) * 0.06)
            var streak = Path()
            streak.move(to: CGPoint(x: cos(angle) * near, y: sin(angle) * near))
            streak.addLine(to: CGPoint(x: cos(angle) * far, y: sin(angle) * far))
            explosion.stroke(streak, with: .color(BombTheme.ink.opacity(pow(1 - progress, 2) * 0.6)),
                             style: StrokeStyle(lineWidth: CGFloat(index % 3 + 1) * unit, lineCap: .round))
        }

        // Sparse shell fragments travel outward with the wave, then disappear.
        for index in 0..<16 {
            let angle = Double(index) * .pi / 8 + 0.17
            let distance = (70 * unit + radius * (0.6 + Double(index % 3) * 0.09))
            var fragment = explosion
            fragment.opacity = max(0, 1 - progress * 1.3)
            fragment.translateBy(x: cos(angle) * distance, y: sin(angle) * distance)
            fragment.rotate(by: .radians(angle + progress * 2))
            let width = CGFloat(12 + index % 3 * 6) * unit
            var shard = Path()
            shard.move(to: CGPoint(x: -width, y: -3 * unit))
            shard.addLine(to: CGPoint(x: width, y: -unit))
            shard.addLine(to: CGPoint(x: width * 0.5, y: 4 * unit))
            shard.addLine(to: CGPoint(x: -width * 0.7, y: 2 * unit))
            shard.closeSubpath()
            fragment.fill(shard, with: .color(BombTheme.ink))
        }

        // Let the wave clear before the printed title lands; it stays readable through the reveal.
        let titleProgress = min(1, max(0, (progress - 0.12) / 0.88))
        guard titleProgress > 0 else { return }
        var texture = context
        texture.opacity = min(1, titleProgress * 4) * 0.65
        drawHalftone(context: texture, size: size, unit: unit)
        drawImpactTitle(context: explosion, progress: titleProgress, unit: unit)
    }

    private func drawImpactTitle(context: GraphicsContext, progress: Double, unit: CGFloat) {
        var print = context
        print.opacity = min(1, progress * 9)

        // A damped arrival gives one firm impact rather than a repeating cartoon bounce.
        let arrival = 1 - exp(-progress * 10) * cos(progress * 9)
        print.scaleBy(x: unit * (0.78 + arrival * 0.22), y: unit * (0.78 + arrival * 0.22))
        print.rotate(by: .degrees(-7 + (1 - arrival) * 4))

        let haloRadius = 142 + 18 * progress
        print.fill(Path(ellipseIn: CGRect(x: -haloRadius, y: -haloRadius,
                                         width: haloRadius * 2, height: haloRadius * 2)),
                   with: .color(BombTheme.yellow.opacity(0.12)))

        // Broken circular engraving and a few tapered rays keep the center uncluttered.
        for index in 0..<3 {
            let radius = 168 + CGFloat(index) * 13 + progress * 14
            var arc = Path()
            arc.addArc(center: .zero, radius: radius,
                       startAngle: .degrees(Double(index) * 120 + 16),
                       endAngle: .degrees(Double(index) * 120 + 101), clockwise: false)
            print.stroke(arc, with: .color(BombTheme.ink.opacity(index == 0 ? 0.3 : 0.12)),
                         style: StrokeStyle(lineWidth: index == 0 ? 1.5 : 0.8, lineCap: .round))
        }
        for index in 0..<10 {
            let angle = Double(index) * .pi / 5 + 0.2
            let inner = 128.0 + Double(index % 3) * 12
            let outer = inner + 22 + Double(index % 2) * 16 + progress * 16
            var ray = Path()
            ray.move(to: CGPoint(x: cos(angle) * inner, y: sin(angle) * inner))
            ray.addLine(to: CGPoint(x: cos(angle - 0.012) * outer, y: sin(angle - 0.012) * outer))
            ray.addLine(to: CGPoint(x: cos(angle + 0.012) * outer, y: sin(angle + 0.012) * outer))
            ray.closeSubpath()
            print.fill(ray, with: .color(BombTheme.ink.opacity(0.45)))
        }

        let headline = Text("BOOM")
            .font(.system(size: 104, weight: .black).width(.condensed))
            .tracking(-5)
        var type = print
        let measuredWidth = type.resolve(headline).measure(in: CGSize(width: 1_000, height: 1_000)).width
        let fit = min(1, 310 / max(1, measuredWidth))
        type.scaleBy(x: fit, y: 1)
        type.draw(headline.foregroundStyle(BombTheme.ink), at: CGPoint(x: 7, y: 9))
        type.draw(headline.foregroundStyle(BombTheme.yellow), at: CGPoint(x: 4, y: 6))
        for index in 0..<8 {
            let angle = Double(index) * .pi / 4
            type.draw(headline.foregroundStyle(BombTheme.paper),
                      at: CGPoint(x: cos(angle) * 1.5, y: sin(angle) * 1.5))
        }
        type.draw(headline.foregroundStyle(BombTheme.ink), at: .zero)

        var emblem = print
        emblem.translateBy(x: 0, y: -88)
        var bolt = Path()
        bolt.move(to: CGPoint(x: 5, y: -18))
        bolt.addLine(to: CGPoint(x: -12, y: 3))
        bolt.addLine(to: CGPoint(x: -2, y: 3))
        bolt.addLine(to: CGPoint(x: -5, y: 18))
        bolt.addLine(to: CGPoint(x: 13, y: -4))
        bolt.addLine(to: CGPoint(x: 3, y: -4))
        bolt.closeSubpath()
        emblem.fill(bolt, with: .color(BombTheme.ink))

        print.draw(Text("OOPS BOMB").font(.system(size: 10, weight: .bold, design: .monospaced))
            .tracking(4).foregroundStyle(BombTheme.ink.opacity(0.7)), at: CGPoint(x: 0, y: 83))
    }
}

#if DEBUG
/// An isolated preview without signing out or changing the saved Firebase account.
struct BombEntryAnimationPreview: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var session = AuthSessionStore()
    @State private var showsDestination = false

    var body: some View {
        BombLaunchView {
            ZStack {
                if showsDestination {
                    AppRootView(playsLaunchAnimation: false)
                        .transition(reduceMotion ? .opacity : .move(edge: .trailing))
                } else {
                    AuthenticationView(session: session, onCompletion: { showsDestination = true })
                        .transition(reduceMotion ? .opacity : .asymmetric(insertion: .opacity, removal: .move(edge: .leading)))
                }
            }
            .animation(reduceMotion ? .easeOut(duration: 0.18) : .smooth(duration: 0.55), value: showsDestination)
        }
    }
}
#endif
