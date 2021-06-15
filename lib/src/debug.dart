/// Enables and disables console logs
/// and debugShowCheckedModeBanner
abstract class Debug {
  static const bool _isEnabled = false; // <- you have to set it here

  static bool get enabled => _isEnabled;

  static void log(dynamic message) {
    if (enabled) {
      print('[ APPDEBUG ] $message');
    }
  }
}
