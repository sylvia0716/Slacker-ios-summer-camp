import UIKit

// 多數畫面用 navigationBarBackButtonHidden(true) 換成自訂返回鍵，系統會連帶停用左緣滑動返回。
// 這裡讓每個導覽堆疊在不是根畫面時，都能重新用滑動返回。
extension UINavigationController: @retroactive UIGestureRecognizerDelegate {
    override open func viewDidLoad() {
        super.viewDidLoad()
        interactivePopGestureRecognizer?.delegate = self
    }

    public func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        viewControllers.count > 1
    }
}
