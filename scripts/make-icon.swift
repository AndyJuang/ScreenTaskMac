import AppKit
let destination = CommandLine.arguments[1]
let size = NSSize(width: 1024, height: 1024)
let image = NSImage(size: size)
image.lockFocus()
let background = NSBezierPath(roundedRect: NSRect(x: 32, y: 32, width: 960, height: 960), xRadius: 214, yRadius: 214)
NSColor(deviceRed: 0.06, green: 0.18, blue: 0.19, alpha: 1).setFill(); background.fill()
let rear = NSBezierPath(roundedRect: NSRect(x: 290, y: 370, width: 580, height: 410), xRadius: 48, yRadius: 48)
NSColor(deviceRed: 0.21, green: 0.47, blue: 0.43, alpha: 1).setFill(); rear.fill()
let front = NSBezierPath(roundedRect: NSRect(x: 150, y: 240, width: 580, height: 410), xRadius: 48, yRadius: 48)
NSColor(deviceRed: 0.55, green: 0.90, blue: 0.79, alpha: 1).setFill(); front.fill()
let screen = NSBezierPath(roundedRect: NSRect(x: 184, y: 292, width: 512, height: 324), xRadius: 24, yRadius: 24)
NSColor(deviceRed: 0.07, green: 0.25, blue: 0.25, alpha: 1).setFill(); screen.fill()
let triangle = NSBezierPath(); triangle.move(to: NSPoint(x: 388, y: 362)); triangle.line(to: NSPoint(x: 388, y: 546)); triangle.line(to: NSPoint(x: 532, y: 454)); triangle.close()
NSColor(deviceRed: 0.64, green: 0.96, blue: 0.86, alpha: 1).setFill(); triangle.fill()
image.unlockFocus()
let bitmap = NSBitmapImageRep(data: image.tiffRepresentation!)!
try bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: destination))
