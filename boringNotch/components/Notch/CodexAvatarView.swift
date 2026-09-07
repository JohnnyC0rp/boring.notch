import AppKit
import Lottie
import SwiftUI

/// Recovered Codex artwork. Activity is supplied by the local task monitor.
struct CodexAvatarView: View {
    let style: CodexAvatarStyle
    let isActive: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Group {
            if style == .smile {
                MinimalFaceFeatures(height: 24, width: 30)
            } else {
                NativeCodexAvatar(style: style, isActive: isActive, reduceMotion: reduceMotion)
            }
        }
        .frame(width: 30, height: 24)
        .accessibilityLabel(isActive ? "Codex is working" : "Codex is idle")
    }
}

private struct NativeCodexAvatar: NSViewRepresentable {
    let style: CodexAvatarStyle
    let isActive: Bool
    let reduceMotion: Bool

    func makeNSView(context: Context) -> CodexAvatarNativeView { CodexAvatarNativeView() }

    func updateNSView(_ view: CodexAvatarNativeView, context: Context) {
        view.update(style: style, isActive: isActive, reduceMotion: reduceMotion)
    }

    static func dismantleNSView(_ view: CodexAvatarNativeView, coordinator: ()) {
        view.stopAnimating()
    }
}

private final class CodexAvatarNativeView: NSView {
    private let thinking = LottieAnimationView()
    private let artwork = CodexAvatarArtworkView()
    private let colorfulArtwork = CodexAvatarArtworkView()
    private var style: CodexAvatarStyle?
    private var requestedActive = false
    private var reduceMotion = false
    private var spinning = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        for view in [thinking, artwork, colorfulArtwork] {
            view.wantsLayer = true
            addSubview(view)
        }
        thinking.contentMode = .scaleAspectFit
        thinking.backgroundBehavior = .pauseAndRestore
        thinking.shouldRasterizeWhenIdle = true
        if let url = Self.resource("codex-thinking-loader", extension: "json") {
            thinking.animation = LottieAnimation.filepath(url.path)
            thinking.setValueProvider(
                ColorValueProvider(LottieColor(r: 1, g: 1, b: 1, a: 1)),
                keypath: AnimationKeypath(keypath: "**.Color")
            )
            thinking.setValueProvider(
                FloatValueProvider(4.9234 * 1.5),
                keypath: AnimationKeypath(keypath: "**.Blossom stroke.Stroke Width")
            )
            thinking.setValueProvider(
                FloatValueProvider(5.742 * 1.5),
                keypath: AnimationKeypath(keypath: "**.Stroke 1.Stroke Width")
            )
        }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layout() {
        super.layout()
        let size = min(bounds.width, bounds.height)
        let rect = NSRect(x: (bounds.width - size) / 2, y: (bounds.height - size) / 2, width: size, height: size)
        thinking.frame = rect
        artwork.frame = rect
        colorfulArtwork.frame = rect
    }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        reconcileAnimation()
    }

    func update(style: CodexAvatarStyle, isActive: Bool, reduceMotion: Bool) {
        if self.style != style {
            stopAnimating()
            self.style = style
            colorfulArtwork.isHidden = style != .iris
            let name = style == .iris ? "codex-iris-resting"
                : style == .codex ? "codex-thinking-static" : "codex-home-icon"
            artwork.image = Self.whiteVector(named: name)
            colorfulArtwork.image = Self.resource("codex-iris-dark", extension: "png").flatMap(NSImage.init(contentsOf:))
        }
        requestedActive = isActive
        self.reduceMotion = reduceMotion
        reconcileAnimation()
    }

    private func reconcileAnimation() {
        let active = requestedActive && window != nil
        let shouldAnimate = active && !reduceMotion
        thinking.isHidden = style != .codex || !shouldAnimate
        artwork.isHidden = style == .codex && shouldAnimate
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        thinking.alphaValue = active ? 0.9 : 0.5
        artwork.alphaValue = style == .iris ? (active ? 0 : 0.45) : (active ? 1 : 0.65)
        colorfulArtwork.alphaValue = active ? 1 : 0
        CATransaction.commit()
        guard shouldAnimate != spinning else { return }
        stopAnimating()
        guard shouldAnimate else { return }
        spinning = true

        switch style {
        case .codex:
            thinking.play(fromProgress: 0, toProgress: 1, loopMode: .loop)
        case .codexSpin:
            addClickSpin()
        case .iris:
            let rotation = CABasicAnimation(keyPath: "transform.rotation.z")
            rotation.fromValue = 0
            // AppKit's unflipped layer coordinates reverse the browser's angle sign.
            rotation.toValue = Double.pi * 2
            rotation.duration = 6
            rotation.repeatCount = .infinity
            colorfulArtwork.artworkLayer.add(rotation, forKey: "codexActivity")
        default:
            break
        }
    }

    func stopAnimating() {
        spinning = false
        thinking.stop()
        artwork.artworkLayer.removeAnimation(forKey: "codexActivity")
        colorfulArtwork.artworkLayer.removeAnimation(forKey: "codexActivity")
    }

    private func addClickSpin() {
        guard let url = Self.resource("codex-spin-keyframes", extension: "json"),
              let data = try? Data(contentsOf: url),
              let motion = try? JSONDecoder().decode(SpinKeyframes.self, from: data) else { return }
        let rotation = CAKeyframeAnimation(keyPath: "transform.rotation.z")
        rotation.duration = 1.1
        rotation.keyTimes = motion.times.map(NSNumber.init(value:))
        rotation.values = motion.degrees.map { -$0 * .pi / 180 }
        let scale = CAKeyframeAnimation(keyPath: "transform.scale")
        scale.duration = 1.1
        scale.keyTimes = rotation.keyTimes
        scale.values = motion.scales
        let group = CAAnimationGroup()
        group.animations = [rotation, scale]
        group.duration = 1.1
        group.repeatCount = .infinity
        artwork.artworkLayer.add(group, forKey: "codexActivity")
    }

    private struct SpinKeyframes: Decodable {
        let times: [Double]
        let degrees: [Double]
        let scales: [Double]
    }

    private static func resource(_ name: String, extension fileExtension: String) -> URL? {
        Bundle.main.url(forResource: name, withExtension: fileExtension, subdirectory: "CodexAvatar")
            ?? Bundle.main.url(forResource: name, withExtension: fileExtension, subdirectory: "Assets/CodexAvatar")
            ?? Bundle.main.url(forResource: name, withExtension: fileExtension)
    }

    private static func whiteVector(named name: String) -> NSImage? {
        guard let url = resource(name, extension: "svg"),
              let source = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        // Keep the recovered paths intact; their original black tint needs a night shift.
        let svg = source
            .replacingOccurrences(of: "fill=\"currentColor\"", with: "fill=\"#ffffff\"")
            .replacingOccurrences(of: "stroke=\"currentColor\"", with: "stroke=\"#ffffff\"")
            .replacingOccurrences(of: "opacity=\"0.3\"", with: "opacity=\"1\"")
            .replacingOccurrences(of: "stroke-width=\"4.9234\"", with: "stroke-width=\"7.3851\"")
            .replacingOccurrences(of: "stroke-width=\"5.742\"", with: "stroke-width=\"8.613\"")
            .replacingOccurrences(of: "stroke-width=\"24\"", with: "stroke-width=\"36\"")
        let outlineWidth = name == "codex-home-icon" ? 20 : 10
        let thickerSVG = svg.replacingOccurrences(
            of: "fill=\"#ffffff\"",
            with: "fill=\"#ffffff\" stroke=\"#ffffff\" stroke-width=\"\(outlineWidth)\" stroke-linejoin=\"round\""
        )
        return NSImage(data: Data(thickerSVG.utf8))
    }
}

private final class CodexAvatarArtworkView: NSView {
    let artworkLayer = CALayer()
    var image: NSImage? {
        didSet {
            artworkLayer.contents = image?.cgImage(forProposedRect: nil, context: nil, hints: nil)
        }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        artworkLayer.name = "CodexAvatarArtwork"
        artworkLayer.contentsGravity = .resizeAspect
        layer?.addSublayer(artworkLayer)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        // AppKit owns the view's backing layer; the artwork gets its own dance floor.
        artworkLayer.bounds = CGRect(origin: .zero, size: bounds.size)
        artworkLayer.position = CGPoint(x: bounds.midX, y: bounds.midY)
        artworkLayer.contentsScale = window?.backingScaleFactor ?? 2
        CATransaction.commit()
    }
}
