import 'package:flutter/widgets.dart';
import 'package:tencent_map_flutter/tencent_map_flutter.dart';

import 'app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await TencentMap.init(agreePrivacy: true);
  runApp(const FamilyNaviApp());
}
