package re.bruge.herbier;

import android.Manifest;
import android.content.Context;
import android.content.Intent;
import android.os.Build;
import android.util.Log;
import androidx.core.app.NotificationManagerCompat;
import androidx.core.content.ContextCompat;
import com.getcapacitor.JSObject;
import com.getcapacitor.PermissionState;
import com.getcapacitor.Plugin;
import com.getcapacitor.PluginCall;
import com.getcapacitor.PluginMethod;
import com.getcapacitor.annotation.CapacitorPlugin;
import com.getcapacitor.annotation.Permission;
import com.getcapacitor.annotation.PermissionCallback;
import java.lang.ref.WeakReference;

/**
 * A foreground service of type dataSync around a long job the WebView runs
 * (« Toute la France », architecture §8; bound by
 * app/bindings/cap_foreground_run.ml). The action sends {@code interrupt}
 * ({@code {reason: "user"}}; {@code "timeout"} when Android 15+ ends the
 * service); the job is the app's to stop. Rejection codes and the answer's
 * shape are read by the binding: keep them in step.
 *
 * <p>State is touched from the plugin thread (calls), the main thread
 * (permission answer, the service's interrupt) and the bridge's destroy:
 * every transition is synchronized on the instance.
 */
@CapacitorPlugin(
    name = "ForegroundRun",
    permissions = @Permission(alias = "notifications", strings = { Manifest.permission.POST_NOTIFICATIONS })
)
public class ForegroundRunPlugin extends Plugin {

    private static final String LOG = "HerbierForegroundRun";
    private static volatile WeakReference<ForegroundRunPlugin> instance = new WeakReference<>(null);

    /** A start not followed by a stop: the app's job is going. */
    private boolean wanted;
    /** The service was asked to start for the current job and has not ended. */
    private boolean started;
    /** Counts the service starts, so the end of a former one leaves the current one alone. */
    private int generation;

    @Override
    public void load() {
        instance = new WeakReference<>(this);
    }

    @Override
    protected void handleOnDestroy() {
        // The activity, and with it the WebView and its job, is gone.
        stopService();
        instance = new WeakReference<>(null);
        super.handleOnDestroy();
    }

    /** The service's entry for its notification's action and its timeout; false when nobody can stop the job. */
    static boolean interrupt(String reason) {
        ForegroundRunPlugin plugin = instance.get();
        if (plugin == null) {
            return false;
        }
        if (!plugin.hasListeners("interrupt")) {
            Log.w(LOG, "interrupt without a listener: the service stops, the job goes on without it");
            return false;
        }
        JSObject data = new JSObject();
        data.put("reason", reason);
        plugin.notifyListeners("interrupt", data);
        return true;
    }

    /** The service ended (stopped, timed out, refused foreground): updates no longer post. */
    static void serviceEnded(int ended) {
        ForegroundRunPlugin plugin = instance.get();
        if (plugin == null) {
            return;
        }
        synchronized (plugin) {
            if (plugin.generation == ended) {
                plugin.started = false;
            }
        }
    }

    /** The notice of a call, or null after rejecting it. */
    private static ForegroundRunService.Notice notice(PluginCall call) {
        JSObject data = call.getData();
        Object title = data.opt("title");
        Object text = data.opt("text");
        Object value = data.opt("value");
        Object max = data.opt("max");
        Object action = data.opt("action");
        if (!(title instanceof String) || ((String) title).isEmpty()) {
            call.reject("title must be a non-empty string", "INVALID_ARGUMENT");
            return null;
        }
        if (text != null && !(text instanceof String)) {
            call.reject("text must be a string", "INVALID_ARGUMENT");
            return null;
        }
        if (action != null && (!(action instanceof String) || ((String) action).isEmpty())) {
            call.reject("action must be a non-empty string", "INVALID_ARGUMENT");
            return null;
        }
        if (!(max instanceof Integer) || (Integer) max < 0) {
            call.reject("max must be an integer >= 0", "INVALID_ARGUMENT");
            return null;
        }
        if (!(value instanceof Integer) || (Integer) value < 0 || (Integer) value > (Integer) max) {
            call.reject("value must be an integer in 0..max", "INVALID_ARGUMENT");
            return null;
        }
        return new ForegroundRunService.Notice((String) title, (String) text, (Integer) value, (Integer) max, (String) action);
    }

    private Intent serviceIntent() {
        return new Intent(getContext(), ForegroundRunService.class);
    }

    private JSObject answer() {
        JSObject ret = new JSObject();
        boolean enabled = NotificationManagerCompat.from(getContext()).areNotificationsEnabled();
        ret.put("notifications", enabled ? "granted" : "denied");
        return ret;
    }

    @PluginMethod
    public void start(PluginCall call) {
        ForegroundRunService.Notice notice = notice(call);
        if (notice == null) {
            return;
        }
        boolean ask;
        synchronized (this) {
            ForegroundRunService.current = notice;
            wanted = true;
            if (started) {
                ForegroundRunService.post(getContext(), notice);
                call.resolve(answer());
                return;
            }
            ask = Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU && getPermissionState("notifications") != PermissionState.GRANTED;
        }
        if (ask) {
            // Asked at every start while not granted; Android stops showing
            // the dialog after two refusals.
            requestPermissionForAlias("notifications", call, "afterPermission");
        } else {
            proceed(call);
        }
    }

    @PermissionCallback
    private void afterPermission(PluginCall call) {
        proceed(call);
    }

    private void proceed(PluginCall call) {
        synchronized (this) {
            // A stop came during the dialog, or another start already started it.
            if (!wanted || started) {
                call.resolve(answer());
                return;
            }
            generation++;
            ForegroundRunService.clearStop();
            try {
                ContextCompat.startForegroundService(
                    getContext(),
                    serviceIntent().setAction(ForegroundRunService.ACTION_START).putExtra(ForegroundRunService.EXTRA_GENERATION, generation)
                );
            } catch (IllegalStateException | SecurityException e) {
                // ForegroundServiceStartNotAllowedException (Android 12+): the
                // app was in the background.
                Log.w(LOG, "start refused: " + e.getClass().getSimpleName());
                wanted = false;
                call.reject("foreground service not allowed", "START_NOT_ALLOWED");
                return;
            }
            started = true;
        }
        call.resolve(answer());
    }

    @PluginMethod
    public void update(PluginCall call) {
        ForegroundRunService.Notice notice = notice(call);
        if (notice == null) {
            return;
        }
        synchronized (this) {
            ForegroundRunService.current = notice;
            // Straight to the notification manager, not through
            // startService: no background-start restriction while the app is
            // in the background. Before the service is foreground, it reads
            // [current] itself. Without the permission the post is dropped,
            // which is what a refusal means.
            if (started) {
                ForegroundRunService.post(getContext(), notice);
            }
        }
        call.resolve();
    }

    @PluginMethod
    public void stop(PluginCall call) {
        stopService();
        call.resolve();
    }

    // A service asked to start but not yet foreground must not be stopped
    // from here (Android would crash the app): it stops itself once
    // foreground.
    private synchronized void stopService() {
        wanted = false;
        started = false;
        Context ctx = getContext();
        if (ForegroundRunService.requestStop()) {
            ctx.stopService(serviceIntent());
        }
        NotificationManagerCompat.from(ctx).cancel(ForegroundRunService.NOTIFICATION_ID);
    }
}
