import SwiftUI

// The setup wizard's raised panel and divider, shared with the installer wizard.
public struct SetupCard<Content: View>: View {
    private let content: Content

    public init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    public var body: some View {
        VStack(spacing: 0) { content }
            .background(BP.raise, in: RoundedRectangle(cornerRadius: BP.radius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: BP.radius, style: .continuous).strokeBorder(BP.line, lineWidth: 1))
    }
}

public struct SetupHairline: View {
    public init() {}

    public var body: some View {
        Rectangle().fill(BP.line).frame(height: 1).padding(.leading, 54)
    }
}
