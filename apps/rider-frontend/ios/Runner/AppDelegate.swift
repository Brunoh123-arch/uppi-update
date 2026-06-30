import UIKit
import Flutter
import GoogleMaps

@main
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GMSServices.provideAPIKey(getGoogleMapsAPIKey())
    GeneratedPluginRegistrant.register(with: self)
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  private func getGoogleMapsAPIKey() -> String {
    // 1. Fallback default key (original key)
    let defaultKey = "AIzaSyAHjeUov0-VHb3AXOmWTb5xBWy00Btdets"
    
    // 2. Try to read .env file from Flutter assets directory
    guard let envPath = Bundle.main.path(forResource: ".env", ofType: nil, inDirectory: "flutter_assets") else {
      return defaultKey
    }
    
    do {
      let content = try String(contentsOfFile: envPath, encoding: .utf8)
      let lines = content.components(separatedBy: .newlines)
      for line in lines {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty || trimmed.hasPrefix("#") { continue }
        let parts = trimmed.components(separatedBy: "=")
        if parts.count >= 2 {
          let key = parts[0].trimmingCharacters(in: .whitespacesAndNewlines)
          if key == "GOOGLE_MAP_API_KEY" {
            let value = parts[1...].joined(separator: "=").trimmingCharacters(in: .whitespacesAndNewlines)
            let cleanValue = value.replacingOccurrences(of: "\"", with: "").replacingOccurrences(of: "'", with: "")
            if !cleanValue.isEmpty {
              return cleanValue
            }
          }
        }
      }
    } catch {
      print("Erro ao carregar .env em AppDelegate: \(error)")
    }
    
    return defaultKey
  }
}
