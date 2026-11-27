// Test client: makes the Wallpaper.framework and WindowManager.framework calls the Dock makes at start (macOS 26.7.2), for a capture with xcap.dylib.
import Foundation
import Wallpaper
import WindowManager
import QuartzCore
let args = CommandLine.arguments
let display = UUID(uuidString: args.count > 1 ? args[1] : "D19AD5BA-D2A3-3EBB-0024-A4187A84FFFE")!
let space = args.count > 2 ? args[2] : ""
let doWM = ProcessInfo.processInfo.environment["NO_WM"] == nil
let doWP = ProcessInfo.processInfo.environment["NO_WP"] == nil
if doWP {
  let m = WallpaperManager()
  m.makeMainDisplay(display)
  do { try m.makeFirstSpace(space: space, display: display); print("makeFirstSpace ok") } catch { print("makeFirstSpace error: \(error)") }
  Task {
    do { let a = try await WallpaperDisplayAssertion(display: display, spaceName: space); print("assertion layer: \(a.layer) contextId=\(String(describing: a.layer.value(forKey: "contextId")))") }
    catch { print("assertion error: \(error)") }
  }
  _ = Unmanaged.passRetained(m)
}
if doWM {
  let pm = WindowManager.shared.createDesktopPeekMonitor()
  do { try pm.begin(); print("peek monitor begun") } catch { print("peek monitor error: \(error)") }
  _ = Unmanaged.passRetained(pm)
}
DispatchQueue.main.asyncAfter(deadline: .now() + 3) { print("done"); exit(0) }
dispatchMain()
