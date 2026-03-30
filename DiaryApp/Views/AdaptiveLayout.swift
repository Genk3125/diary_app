import SwiftUI

private struct RegularWidthContentModifier: ViewModifier {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    let maxWidth: CGFloat

    func body(content: Content) -> some View {
        content
            .frame(
                maxWidth: horizontalSizeClass == .regular ? maxWidth : .infinity,
                alignment: .leading
            )
            .frame(maxWidth: .infinity, alignment: .center)
    }
}

extension View {
    func regularWidthContent(maxWidth: CGFloat = 760) -> some View {
        modifier(RegularWidthContentModifier(maxWidth: maxWidth))
    }
}
