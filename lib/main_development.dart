import 'package:crack_app/app/app.dart';
import 'package:crack_app/bootstrap.dart';

Future<void> main() async {
  await bootstrap(() => const App());
}
