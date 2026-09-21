import 'dart:io';
import 'package:path/path.dart' as p;
import 'tool_support.dart';

/// Configure only the disposable macOS host. No window or Flutter view is created.
void configureHeadlessHost(String host) {
  final runner = p.join(host, 'macos', 'Runner');
  final plist = File(p.join(runner, 'Info.plist'));
  if (!plist.readAsStringSync().contains('<key>LSBackgroundOnly</key>')) {
    plist.writeAsStringSync(replaceOnce(
        plist.readAsStringSync(),
        '\t<key>NSMainNibFile</key>\n\t<string>MainMenu</string>',
        '\t<key>LSBackgroundOnly</key>\n\t<true/>'));
  }
  final project = File(p.join(host, 'macos/Runner.xcodeproj/project.pbxproj'));
  project.writeAsStringSync(project.readAsStringSync().replaceAll(
      RegExp(r'^.*MainMenu\.xib in Resources.*\n', multiLine: true), ''));
  File(p.join(runner, 'AppDelegate.swift')).writeAsStringSync('''import Cocoa
import FlutterMacOS

@main
class AppDelegate: FlutterAppDelegate {
  private var engine: FlutterEngine?

  // Bypass NSApplicationMain's nib loading and UI restoration.
  static func main() {
    let app = NSApplication.shared
    app.setActivationPolicy(.prohibited)
    let delegate = AppDelegate()
    app.delegate = delegate
    withExtendedLifetime(delegate) { app.run() }
  }

  override func applicationWillFinishLaunching(_ notification: Notification) {
    NSApp.setActivationPolicy(.prohibited)
    super.applicationWillFinishLaunching(notification)
    setenv("LOON_PROFILE_HEADLESS", "true", 1)

    let engine = FlutterEngine(name: "loon_profile", project: nil,
                               allowHeadlessExecution: true)
    self.engine = engine
    RegisterGeneratedPlugins(registry: engine)
    guard engine.run(withEntrypoint: nil) else {
      fputs("Could not start the headless benchmark engine\\n", stderr)
      exit(1)
    }
    precondition(NSApp.windows.isEmpty && NSApp.activationPolicy() == .prohibited)
  }
}
''');
}
