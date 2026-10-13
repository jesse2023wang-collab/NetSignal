import Cocoa

class SignalIcon {
    static func generateImage(quality: NetworkQuality, size: NSSize = NSSize(width: 20, height: 20)) -> NSImage {
        let image = NSImage(size: size)
        image.lockFocus()

        let ctx = NSGraphicsContext.current!.cgContext
        ctx.setShouldAntialias(true)

        let barCount = 4
        let barWidth: CGFloat = 3
        let barSpacing: CGFloat = 1.5
        let totalWidth = CGFloat(barCount) * barWidth + CGFloat(barCount - 1) * barSpacing
        let startX = (size.width - totalWidth) / 2
        let baseY: CGFloat = 3
        let maxBarHeight: CGFloat = size.height - baseY - 2

        let activeColor = NSColor.labelColor
        let inactiveColor = NSColor.separatorColor.withAlphaComponent(0.25)

        for i in 0..<barCount {
            let barHeight = maxBarHeight * (CGFloat(i + 1) / CGFloat(barCount))
            let x = startX + CGFloat(i) * (barWidth + barSpacing)
            let y = baseY
            let rect = NSRect(x: x, y: y, width: barWidth, height: barHeight)
            let path = NSBezierPath(roundedRect: rect, xRadius: 1.0, yRadius: 1.0)

            if i < quality.rawValue {
                activeColor.setFill()
            } else {
                inactiveColor.setFill()
            }
            path.fill()
        }

        image.unlockFocus()
        // 模板图像：由系统按菜单栏外观着色（浅色黑 / 深色白）
        image.isTemplate = true
        return image
    }

    // 加载应用图标（从 Resources/AppIcon.png，用于弹窗）
    static func drawAppIcon(size: NSSize = NSSize(width: 64, height: 64)) -> NSImage {
        let output = NSImage(size: size)
        output.lockFocus()
        let ctx = NSGraphicsContext.current!.cgContext
        ctx.setShouldAntialias(true)

        // 先画不透明白色圆角背景底板，避免与弹窗背景融合
        let cornerRadius: CGFloat = size.width * 0.18
        let bgRect = NSRect(origin: .zero, size: size)
        let bgPath = NSBezierPath(roundedRect: bgRect, xRadius: cornerRadius, yRadius: cornerRadius)
        NSColor.white.setFill()
        bgPath.fill()

        // 优先从 Bundle.main 加载（安装后的 .app）
        if let url = Bundle.main.url(forResource: "AppIcon", withExtension: "png"),
           let icon = NSImage(contentsOf: url) {
            icon.draw(in: NSRect(origin: .zero, size: size),
                      from: .zero,
                      operation: .sourceOver,
                      fraction: 1.0)
        } else {
            // 回退：代码绘制绿色信号条
            let barCount = 4
            let barWidth: CGFloat = size.width * 9.0 / 64.0
            let barSpacing: CGFloat = size.width * 5.0 / 64.0
            let totalWidth = CGFloat(barCount) * barWidth + CGFloat(barCount - 1) * barSpacing
            let startX = (size.width - totalWidth) / 2
            let baseY: CGFloat = size.height * 8.0 / 64.0
            let maxBarHeight: CGFloat = size.height - baseY - size.height * 8.0 / 64.0

            let barColor = NSColor(red: 76.0/255.0, green: 175.0/255.0, blue: 80.0/255.0, alpha: 1.0)

            for i in 0..<barCount {
                let barHeight = maxBarHeight * (CGFloat(i + 1) / CGFloat(barCount))
                let x = startX + CGFloat(i) * (barWidth + barSpacing)
                let y = baseY
                let rect = NSRect(x: x, y: y, width: barWidth, height: barHeight)
                let path = NSBezierPath(roundedRect: rect, xRadius: barWidth / 3, yRadius: barWidth / 3)
                barColor.setFill()
                path.fill()
            }
        }

        output.unlockFocus()
        return output
    }
}
