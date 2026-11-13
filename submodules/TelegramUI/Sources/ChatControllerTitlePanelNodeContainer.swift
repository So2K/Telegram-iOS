import Foundation
import UIKit
import AsyncDisplayKit

final class ChatControllerTitlePanelNodeContainer: ASDisplayNode {
    var hitTestExcludeInsets = UIEdgeInsets()
    
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        if point.x < self.hitTestExcludeInsets.left {
            return nil
        }
        
        // SuperGram: iterate front to back (standard UIKit hit testing order). Iterating in subview
        // order returned the lowest panel first, so a control that was visually on top could lose the
        // touch to a panel below it.
        for subview in self.view.subviews.reversed() {
            if let result = subview.hitTest(self.view.convert(point, to: subview), with: event) {
                return result
            }
        }
        return nil
    }
}
