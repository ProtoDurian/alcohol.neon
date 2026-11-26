package cloud.atomi.alcohol_neon

import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine

// FlutterFragmentActivity, not FlutterActivity: airwallex_payment_flutter casts
// the host activity to androidx ComponentActivity, and FlutterActivity isn't one.
class MainActivity : FlutterFragmentActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        NextUpNotification.register(this, flutterEngine.dartExecutor.binaryMessenger)
    }
}
