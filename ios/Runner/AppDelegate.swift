import Flutter
import UIKit
import QMapKit

@main
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // 设置腾讯地图 Key
    QMapServices.shared().apiKey = "PW7BZ-MGAYW-HBYRD-YJSLR-ABPKQ-C4BEJ"
    GeneratedPluginRegistrant.register(with: self)
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
}
