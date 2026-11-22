package re.bruge.herbier;

import android.view.KeyEvent;
import com.getcapacitor.JSObject;
import com.getcapacitor.Plugin;
import com.getcapacitor.PluginCall;
import com.getcapacitor.PluginMethod;
import com.getcapacitor.annotation.CapacitorPlugin;
import java.lang.ref.WeakReference;

/**
 * The volume-down key as a shutter (4d « Noter », bound by
 * app/bindings/cap_volume_key.ml). Between {@code enable} and {@code disable},
 * and only while a {@code volumeDown} listener is registered, MainActivity
 * hands the key to {@link #handle}: the press is consumed (no volume change,
 * no volume panel) and posts one {@code volumeDown} event; its repeats (the
 * key held) and its release are consumed silently. Everywhere else, volume up
 * always, and with the app in the background the key reaches the system.
 *
 * <p>{@code enabled} is written from the plugin thread and read on the main
 * thread; {@code swallowing} is main-thread only.
 */
@CapacitorPlugin(name = "VolumeKey")
public class VolumeKeyPlugin extends Plugin {

    static final String EVENT = "volumeDown";
    private static volatile WeakReference<VolumeKeyPlugin> instance = new WeakReference<>(null);

    private volatile boolean enabled;
    /** A press was consumed: its repeats and its release are too, even after a disable. */
    private boolean swallowing;

    @Override
    public void load() {
        instance = new WeakReference<>(this);
    }

    @Override
    protected void handleOnDestroy() {
        enabled = false;
        instance = new WeakReference<>(null);
        super.handleOnDestroy();
    }

    /** MainActivity's dispatchKeyEvent, main thread: true when the event is consumed. */
    static boolean handle(KeyEvent event) {
        if (event.getKeyCode() != KeyEvent.KEYCODE_VOLUME_DOWN) {
            return false;
        }
        VolumeKeyPlugin plugin = instance.get();
        if (plugin == null) {
            return false;
        }
        switch (event.getAction()) {
            case KeyEvent.ACTION_DOWN:
                if (event.getRepeatCount() > 0) {
                    return plugin.swallowing;
                }
                // A reload of the WebView leaves no listener: the key is the
                // system's again.
                if (!plugin.enabled || !plugin.hasListeners(EVENT)) {
                    plugin.swallowing = false;
                    return false;
                }
                plugin.swallowing = true;
                plugin.notifyListeners(EVENT, new JSObject());
                return true;
            case KeyEvent.ACTION_UP:
                boolean consumed = plugin.swallowing;
                plugin.swallowing = false;
                return consumed;
            default:
                return plugin.swallowing;
        }
    }

    @PluginMethod
    public void enable(PluginCall call) {
        enabled = true;
        call.resolve();
    }

    @PluginMethod
    public void disable(PluginCall call) {
        enabled = false;
        call.resolve();
    }
}
