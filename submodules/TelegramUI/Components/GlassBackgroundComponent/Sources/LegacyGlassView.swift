import Foundation
import UIKit
import Display
import ComponentFlow

private let backdropLayerClass: NSObject? = {
    let name = ("CA" as NSString).appendingFormat("BackdropLayer")
    if let cls = NSClassFromString(name as String) as AnyObject as? NSObject {
        return cls
    }
    return nil
}()

@inline(__always)
private func getMethod<T>(object: NSObject, selector: String) -> T? {
    guard let method = object.method(for: NSSelectorFromString(selector)) else {
        return nil
    }
    return unsafeBitCast(method, to: T.self)
}

private var cachedBackdropLayerAllocMethod: (@convention(c) (AnyObject, Selector) -> NSObject?, Selector)?
private func invokeBackdropLayerCreateMethod() -> NSObject? {
    guard let backdropLayerClass = backdropLayerClass else {
        return nil
    }
    if let cachedBackdropLayerAllocMethod {
        return cachedBackdropLayerAllocMethod.0(backdropLayerClass, cachedBackdropLayerAllocMethod.1)
    } else {
        let method: (@convention(c) (AnyObject, Selector) -> NSObject?)? = getMethod(object: backdropLayerClass, selector: "alloc")
        if let method {
            let selector = NSSelectorFromString("alloc")
            cachedBackdropLayerAllocMethod = (method, selector)
            return method(backdropLayerClass, selector)
        } else {
            return nil
        }
    }
}

private var cachedBackdropLayerInitMethod: (@convention(c) (NSObject, Selector) -> NSObject?, Selector)?
private func invokeBackdropLayerInitMethod(object: NSObject) -> NSObject? {
    if let cachedBackdropLayerInitMethod {
        return cachedBackdropLayerInitMethod.0(object, cachedBackdropLayerInitMethod.1)
    } else {
        let method: (@convention(c) (AnyObject, Selector) -> NSObject?)? = getMethod(object: object, selector: "init")
        if let method {
            let selector = NSSelectorFromString("init")
            cachedBackdropLayerInitMethod = (method, selector)
            return method(object, selector)
        } else {
            return nil
        }
    }
}

public func createBackdropLayer() -> CALayer? {
    return invokeBackdropLayerCreateMethod().flatMap(invokeBackdropLayerInitMethod) as? CALayer
}


private var cachedBackdropLayerSetScaleMethod: (@convention(c) (NSObject, Selector, Double) -> Void, Selector)?
private func invokeBackdropLayerSetScaleMethod(object: NSObject, scale: Double) {
    if let cachedBackdropLayerSetScaleMethod {
        cachedBackdropLayerSetScaleMethod.0(object, cachedBackdropLayerSetScaleMethod.1, scale)
    } else {
        let method: (@convention(c) (AnyObject, Selector, Double) -> Void)? = getMethod(object: object, selector: "setScale:")
        if let method {
            let selector = NSSelectorFromString("setScale:")
            cachedBackdropLayerSetScaleMethod = (method, selector)
            return method(object, selector, scale)
        }
    }
}

private final class BackdropLayerDelegate: NSObject, CALayerDelegate {
    func action(for layer: CALayer, forKey event: String) -> CAAction? {
        return nullAction
    }
}

final class LegacyGlassView: UIView {
    enum Style {
        case normal
        case clear
    }
    
    private struct Params: Equatable {
        let size: CGSize
        let shape: GlassBackgroundView.Shape
        let style: Style
        
        init(size: CGSize, shape: GlassBackgroundView.Shape, style: Style) {
            self.size = size
            self.shape = shape
            self.style = style
        }
    }
    
    private var params: Params?
    private var maskLayer: CAShapeLayer?
    
    private let backdropLayer: CALayer?
    private let backdropLayerDelegate: BackdropLayerDelegate
    
    override init(frame: CGRect) {
        self.backdropLayerDelegate = BackdropLayerDelegate()
        self.backdropLayer = createBackdropLayer()
        
        super.init(frame: frame)
        
        self.layer.cornerCurve = .continuous
        self.clipsToBounds = true
        
        if let backdropLayer = self.backdropLayer {
            self.layer.addSublayer(backdropLayer)
            backdropLayer.delegate = self.backdropLayerDelegate
            
            invokeBackdropLayerSetScaleMethod(object: backdropLayer, scale: 1.0)
            backdropLayer.rasterizationScale = 1.0
        }
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    func update(size: CGSize, cornerRadius: CGFloat, style: Style, transition: ComponentTransition) {
        self.update(size: size, shape: .roundedRect(cornerRadius: cornerRadius), style: style, transition: transition)
    }

    func update(size: CGSize, shape: GlassBackgroundView.Shape, style: Style, transition: ComponentTransition) {
        let params = Params(size: size, shape: shape, style: style)
        let previousParams = self.params
        if self.params == params {
            return
        }
        self.params = params
        
        guard let backdropLayer = self.backdropLayer else {
            return
        }
        
        if previousParams?.style != style {
            if let blurFilter = CALayer.blur() {
                switch style {
                case .clear:
                    blurFilter.setValue(6.0 as NSNumber, forKey: "inputRadius")
                case .normal:
                    blurFilter.setValue(8.0 as NSNumber, forKey: "inputRadius")
                }

                backdropLayer.filters = [blurFilter]
            }
        }
        
        switch shape {
        case let .roundedRect(cornerRadius):
            self.maskLayer = nil
            self.layer.mask = nil
            transition.setCornerRadius(layer: self.layer, cornerRadius: cornerRadius)
        case let .customRoundedRect(cornerRadii):
            transition.setCornerRadius(layer: self.layer, cornerRadius: 0.0)

            let maskLayer: CAShapeLayer
            if let current = self.maskLayer {
                maskLayer = current
            } else {
                maskLayer = CAShapeLayer()
                maskLayer.fillColor = UIColor.black.cgColor
                self.maskLayer = maskLayer
                self.layer.mask = maskLayer
            }
            transition.setFrame(layer: maskLayer, frame: CGRect(origin: CGPoint(), size: size))
            transition.setShapeLayerPath(layer: maskLayer, path: GlassBackgroundView.generateRoundedRectPath(size: size, cornerRadii: cornerRadii))
        }
        transition.setFrame(layer: backdropLayer, frame: CGRect(origin: CGPoint(), size: size))
    }
}
