import Foundation
import UIKit
import Display
import TelegramPresentationData
import ComponentFlow
import GlassBackgroundComponent
import MultilineTextComponent
import AppBundle

public final class VideoPlaybackControlsComponent: Component {
    public struct LayoutParams: Equatable {
        public var sideButtonSize: CGFloat
        public var centerButtonSize: CGFloat
        public var spacing: CGFloat

        public init(sideButtonSize: CGFloat, centerButtonSize: CGFloat, spacing: CGFloat) {
            self.sideButtonSize = sideButtonSize
            self.centerButtonSize = centerButtonSize
            self.spacing = spacing
        }
    }
    
    let layoutParams: LayoutParams
    let isVisible: Bool
    let isPlaying: Bool
    let displaySeekControls: Bool
    let togglePlayback: () -> Void
    let seek: (Bool) -> Void
    
    public init(
        layoutParams: LayoutParams,
        isVisible: Bool,
        isPlaying: Bool,
        displaySeekControls: Bool,
        togglePlayback: @escaping () -> Void,
        seek: @escaping (Bool) -> Void
    ) {
        self.layoutParams = layoutParams
        self.isVisible = isVisible
        self.isPlaying = isPlaying
        self.displaySeekControls = displaySeekControls
        self.togglePlayback = togglePlayback
        self.seek = seek
    }
    
    public static func ==(lhs: VideoPlaybackControlsComponent, rhs: VideoPlaybackControlsComponent) -> Bool {
        if lhs.layoutParams != rhs.layoutParams {
            return false
        }
        if lhs.isVisible != rhs.isVisible {
            return false
        }
        if lhs.isPlaying != rhs.isPlaying {
            return false
        }
        if lhs.displaySeekControls != rhs.displaySeekControls {
            return false
        }
        return true
    }
    
    public final class View: UIView {
        private let backgroundContainer: GlassBackgroundContainerView
        private let leftButtonBackgroundView: GlassBackgroundView
        private let leftIconView: PlaybackIconView
        private let rightButtonBackgroundView: GlassBackgroundView
        private let rightIconView: PlaybackIconView
        private let centerButtonView: UIView
        private let centerButtonIconView: PlayPauseGlyphView
        private let leftSeekFeedbackView: UIView
        private let leftSeekFeedbackIconView: PlaybackIconView
        private let rightSeekFeedbackView: UIView
        private let rightSeekFeedbackIconView: PlaybackIconView
        
        private var component: VideoPlaybackControlsComponent?
        private weak var state: EmptyComponentState?
        
        public override init(frame: CGRect) {
            self.backgroundContainer = GlassBackgroundContainerView()
            
            self.leftButtonBackgroundView = GlassBackgroundView()
            self.leftIconView = PlaybackIconView(isForward: false)
            self.leftIconView.isUserInteractionEnabled = false
            self.leftButtonBackgroundView.contentView.addSubview(self.leftIconView)
            
            self.rightButtonBackgroundView = GlassBackgroundView()
            self.rightIconView = PlaybackIconView(isForward: true)
            self.rightIconView.isUserInteractionEnabled = false
            self.rightButtonBackgroundView.contentView.addSubview(self.rightIconView)
            
            self.centerButtonView = UIView()
            self.centerButtonIconView = PlayPauseGlyphView()
            self.centerButtonIconView.isUserInteractionEnabled = false
            self.centerButtonView.addSubview(self.centerButtonIconView)

            self.leftSeekFeedbackView = UIView()
            self.leftSeekFeedbackIconView = PlaybackIconView(isForward: false)
            self.rightSeekFeedbackView = UIView()
            self.rightSeekFeedbackIconView = PlaybackIconView(isForward: true)
            
            super.init(frame: frame)
            
            self.addSubview(self.backgroundContainer)
            
            self.backgroundContainer.contentView.addSubview(self.leftButtonBackgroundView)
            self.backgroundContainer.contentView.addSubview(self.rightButtonBackgroundView)
            self.backgroundContainer.contentView.addSubview(self.centerButtonView)

            for (feedbackView, iconView) in [(self.leftSeekFeedbackView, self.leftSeekFeedbackIconView), (self.rightSeekFeedbackView, self.rightSeekFeedbackIconView)] {
                feedbackView.alpha = 0.0
                feedbackView.isUserInteractionEnabled = false
                feedbackView.backgroundColor = UIColor(white: 0.0, alpha: 0.42)
                feedbackView.layer.masksToBounds = true
                iconView.isUserInteractionEnabled = false
                feedbackView.addSubview(iconView)
                self.addSubview(feedbackView)
            }

            self.leftButtonBackgroundView.contentView.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(self.onLeftTapGesture(_:))))
            self.rightButtonBackgroundView.contentView.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(self.onRightTapGesture(_:))))
            self.centerButtonView.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(self.onTapGesture(_:))))
        }
        
        required public init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }
        
        deinit {
        }
        
        @objc private func onLeftTapGesture(_ gesture: UITapGestureRecognizer) {
            guard let component = self.component else {
                return
            }
            if case .ended = gesture.state {
                self.animateSeekFeedback(isForward: false)
                component.seek(false)
            }
        }
        
        @objc private func onRightTapGesture(_ gesture: UITapGestureRecognizer) {
            guard let component = self.component else {
                return
            }
            if case .ended = gesture.state {
                self.animateSeekFeedback(isForward: true)
                component.seek(true)
            }
        }
        
        @objc private func onTapGesture(_ gesture: UITapGestureRecognizer) {
            guard let component = self.component else {
                return
            }
            if case .ended = gesture.state {
                component.togglePlayback()
            }
        }
        
        override public func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
            guard let result = super.hitTest(point, with: event) else {
                return nil
            }
            if result === self {
                return nil
            }
            return result
        }

        public func animateSeekFeedback(isForward: Bool) {
            let feedbackView = isForward ? self.rightSeekFeedbackView : self.leftSeekFeedbackView
            feedbackView.layer.removeAllAnimations()
            feedbackView.alpha = 0.0
            feedbackView.transform = CGAffineTransform(scaleX: 0.78, y: 0.78)

            UIView.animate(withDuration: 0.1, delay: 0.0, options: [.allowUserInteraction, .curveEaseOut], animations: {
                feedbackView.alpha = 1.0
                feedbackView.transform = .identity
            }, completion: { _ in
                UIView.animate(withDuration: 0.12, delay: 0.16, options: [.allowUserInteraction, .curveEaseIn], animations: {
                    feedbackView.alpha = 0.0
                    feedbackView.transform = CGAffineTransform(scaleX: 1.08, y: 1.08)
                }, completion: nil)
            })
        }
        
        func update(component: VideoPlaybackControlsComponent, availableSize: CGSize, state: EmptyComponentState, environment: Environment<Empty>, transition: ComponentTransition) -> CGSize {
            let isVisibleChanged = self.component?.isVisible != component.isVisible
            
            self.component = component
            self.state = state
            
            self.isUserInteractionEnabled = component.isVisible
            
            let containerInset: CGFloat = 18.0
            
            let size = CGSize(width: component.layoutParams.sideButtonSize * 2.0 + component.layoutParams.centerButtonSize + component.layoutParams.spacing * 2.0, height: component.layoutParams.centerButtonSize)
            
            let leftButtonFrame = CGRect(origin: CGPoint(x: 0.0, y: floorToScreenPixels((size.height - component.layoutParams.sideButtonSize) * 0.5)), size: CGSize(width: component.layoutParams.sideButtonSize, height: component.layoutParams.sideButtonSize)).offsetBy(dx: containerInset, dy: containerInset)
            let centerButtonFrame = CGRect(origin: CGPoint(x: component.layoutParams.sideButtonSize + component.layoutParams.spacing, y: floorToScreenPixels((size.height - component.layoutParams.centerButtonSize) * 0.5)), size: CGSize(width: component.layoutParams.centerButtonSize, height: component.layoutParams.centerButtonSize)).offsetBy(dx: containerInset, dy: containerInset)
            let rightButtonFrame = CGRect(origin: CGPoint(x: size.width - component.layoutParams.sideButtonSize, y: floorToScreenPixels((size.height - component.layoutParams.sideButtonSize) * 0.5)), size: CGSize(width: component.layoutParams.sideButtonSize, height: component.layoutParams.sideButtonSize)).offsetBy(dx: containerInset, dy: containerInset)
            
            if isVisibleChanged && !transition.animation.isImmediate {
                self.backgroundContainer.isHidden = true
                self.backgroundContainer.isHidden = false
            }
            
            transition.setFrame(view: self.backgroundContainer, frame: CGRect(origin: CGPoint(), size: size).insetBy(dx: -containerInset, dy: -containerInset))
            self.backgroundContainer.update(size: CGSize(width: size.width + containerInset * 2.0, height: size.height + containerInset * 2.0), isDark: true, transition: transition)
            
            let areSideButtonsVisible = component.isVisible && component.displaySeekControls
            let buttonsTintColor: GlassBackgroundView.TintColor = .init(kind: .custom(style: .clear, color: UIColor(white: 0.0, alpha: 0.2)))
            
            transition.setFrame(view: self.leftButtonBackgroundView, frame: leftButtonFrame)
            self.leftButtonBackgroundView.update(size: leftButtonFrame.size, cornerRadius: leftButtonFrame.height * 0.5, isDark: true, tintColor: buttonsTintColor, isInteractive: true, isVisible: areSideButtonsVisible, transition: transition)
            transition.setFrame(view: self.leftIconView, frame: CGRect(origin: CGPoint(), size: leftButtonFrame.size))
            self.leftIconView.update(size: leftButtonFrame.size)
            transition.setAlpha(view: self.leftIconView, alpha: areSideButtonsVisible ? 1.0 : 0.0)
            transition.setBlur(layer: self.leftIconView.layer, radius: areSideButtonsVisible ? 0.0 : 10.0)
            self.leftButtonBackgroundView.isUserInteractionEnabled = areSideButtonsVisible
            
            transition.setFrame(view: self.rightButtonBackgroundView, frame: rightButtonFrame)
            self.rightButtonBackgroundView.update(size: rightButtonFrame.size, cornerRadius: rightButtonFrame.height * 0.5, isDark: true, tintColor: buttonsTintColor, isInteractive: true, isVisible: areSideButtonsVisible, transition: transition)
            transition.setFrame(view: self.rightIconView, frame: CGRect(origin: CGPoint(), size: rightButtonFrame.size))
            self.rightIconView.update(size: rightButtonFrame.size)
            transition.setAlpha(view: self.rightIconView, alpha: areSideButtonsVisible ? 1.0 : 0.0)
            transition.setBlur(layer: self.rightIconView.layer, radius: areSideButtonsVisible ? 0.0 : 10.0)
            self.rightButtonBackgroundView.isUserInteractionEnabled = areSideButtonsVisible

            for (feedbackView, iconView, frame) in [(self.leftSeekFeedbackView, self.leftSeekFeedbackIconView, leftButtonFrame), (self.rightSeekFeedbackView, self.rightSeekFeedbackIconView, rightButtonFrame)] {
                feedbackView.frame = frame
                feedbackView.layer.cornerRadius = frame.height * 0.5
                iconView.frame = CGRect(origin: CGPoint(), size: frame.size)
                iconView.update(size: frame.size)
            }

            transition.setFrame(view: self.centerButtonView, frame: centerButtonFrame)
            self.centerButtonView.isUserInteractionEnabled = component.isVisible
            transition.setAlpha(view: self.centerButtonView, alpha: component.isVisible ? 1.0 : 0.0)

            let centerButtonIconSize = CGSize(width: 24.0, height: 24.0)
            transition.setFrame(
                view: self.centerButtonIconView,
                frame: centerButtonIconSize.centered(in: CGRect(origin: CGPoint(), size: centerButtonFrame.size)).offsetBy(dx: component.isPlaying ? 0.0 : 1.0, dy: 0.0)
            )
            self.centerButtonIconView.update(isPlaying: component.isPlaying)
            
            return size
        }
    }
    
    public func makeView() -> View {
        return View(frame: CGRect())
    }
    
    public func update(view: View, availableSize: CGSize, state: EmptyComponentState, environment: Environment<Empty>, transition: ComponentTransition) -> CGSize {
        return view.update(component: self, availableSize: availableSize, state: state, environment: environment, transition: transition)
    }
}

private final class PlayPauseGlyphView: UIView {
    private var isPlaying = false

    override init(frame: CGRect) {
        super.init(frame: frame)
        self.isOpaque = false
        self.backgroundColor = .clear
        self.contentMode = .redraw
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func update(isPlaying: Bool) {
        guard self.isPlaying != isPlaying else {
            return
        }
        self.isPlaying = isPlaying
        self.setNeedsDisplay()
    }

    override func draw(_ rect: CGRect) {
        UIColor.white.setFill()

        if self.isPlaying {
            let barSize = CGSize(width: 4.0, height: 14.0)
            let gap: CGFloat = 4.0
            let totalWidth = barSize.width * 2.0 + gap
            let origin = CGPoint(x: floor((rect.width - totalWidth) * 0.5), y: floor((rect.height - barSize.height) * 0.5))
            UIBezierPath(roundedRect: CGRect(origin: origin, size: barSize), cornerRadius: 2.0).fill()
            UIBezierPath(roundedRect: CGRect(origin: CGPoint(x: origin.x + barSize.width + gap, y: origin.y), size: barSize), cornerRadius: 2.0).fill()
        } else {
            let path = UIBezierPath()
            path.move(to: CGPoint(x: 7.0, y: 4.5))
            path.addLine(to: CGPoint(x: 19.0, y: 12.0))
            path.addLine(to: CGPoint(x: 7.0, y: 19.5))
            path.close()
            path.fill()
        }
    }
}

private let circleDiameter: CGFloat = 80.0

private final class PlaybackIconView: HighlightTrackingButton {
    let backgroundIconView: UIImageView
    let text = ComponentView<Empty>()
    
    let isForward: Bool

    var isPressing = false {
        didSet {
            if self.isPressing != oldValue && !self.isPressing {
                self.highligthedChanged(false)
            }
        }
    }
    
    init(isForward: Bool) {
        self.isForward = isForward
        
        self.backgroundIconView = UIImageView(image: UIImage(bundleImageName: isForward ? "Media Gallery/ForwardButton" : "Media Gallery/BackwardButton"))
        
        super.init(frame: CGRect())
        
        self.addSubview(self.backgroundIconView)
        
        self.highligthedChanged = { [weak self] highlighted in
            guard let self else {
                return
            }
            if highlighted {
                let transition: ContainedViewLayoutTransition = .animated(duration: 0.18, curve: .linear)
                let angle = CGFloat.pi / 4.0 + 0.226
                transition.updateTransformRotation(view: self.backgroundIconView, angle: self.isForward ? angle : -angle)
            } else if !self.isPressing {
                let transition: ContainedViewLayoutTransition = .animated(duration: 0.2, curve: .linear)
                transition.updateTransformRotation(view: self.backgroundIconView, angle: 0.0)
            }
        }
    }
    
    required public init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    func update(size: CGSize) {
        if let image = self.backgroundIconView.image {
            let factor: CGFloat = 1.1
            self.backgroundIconView.frame = CGSize(width: floor(image.size.width * factor), height: floor(image.size.height * factor)).centered(in: CGRect(origin: CGPoint(), size: size))
        }
        
        let textSize = self.text.update(
            transition: .immediate,
            component: AnyComponent(MultilineTextComponent(
                text: .plain(NSAttributedString(string: "5", font: Font.with(size: 14.0, design: .round, weight: .semibold, traits: []), textColor: .white))
            )),
            environment: {},
            containerSize: size
        )
        if let textView = self.text.view {
            if textView.superview == nil {
                self.addSubview(textView)
            }
            textView.frame = CGRect(origin: CGPoint(x: floorToScreenPixels((size.width - textSize.width) / 2.0), y: floorToScreenPixels((size.height - textSize.height) / 2.0) + UIScreenPixel), size: textSize)
        }
    }
}
