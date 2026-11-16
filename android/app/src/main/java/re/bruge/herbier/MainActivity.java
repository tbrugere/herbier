package re.bruge.herbier;

import android.content.Intent;
import android.os.Bundle;
import androidx.core.splashscreen.SplashScreen;
import com.getcapacitor.BridgeActivity;

public class MainActivity extends BridgeActivity {

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        // The launch theme's splash (styles.xml), dismissed at the first
        // frame; it also switches to postSplashScreenTheme.
        SplashScreen.installSplashScreen(this);
        // BridgeActivity.onCreate hands getIntent() to the plugins, which
        // deliver a VIEW or SEND as a new link or share (4j). An activity
        // recreated after process death, or relaunched from recents, still
        // carries the intent that first started the task: it was handled
        // already, so it must not open 4j again.
        boolean fromHistory =
            (getIntent().getFlags() & Intent.FLAG_ACTIVITY_LAUNCHED_FROM_HISTORY) != 0;
        if (savedInstanceState != null || fromHistory) {
            setIntent(new Intent(Intent.ACTION_MAIN));
        }
        // Inline plugins are registered by hand, before the bridge is built.
        registerPlugin(GoogleAuthorizationPlugin.class);
        registerPlugin(UploaderPlugin.class);
        super.onCreate(savedInstanceState);
    }
}
