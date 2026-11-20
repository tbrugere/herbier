package re.bruge.herbier;

import android.annotation.SuppressLint;
import android.app.Notification;
import android.app.NotificationChannel;
import android.app.NotificationManager;
import android.app.PendingIntent;
import android.app.Service;
import android.content.Context;
import android.content.Intent;
import android.content.pm.ServiceInfo;
import android.os.Build;
import android.os.IBinder;
import android.util.Log;
import androidx.core.app.NotificationCompat;
import androidx.core.app.NotificationManagerCompat;
import androidx.core.app.ServiceCompat;

/**
 * The foreground service of {@link ForegroundRunPlugin} (architecture §8):
 * type dataSync, one ongoing, silent notification showing the
 * plugin's latest {@link Notice}. It keeps the process at foreground priority
 * while the WebView runs a long job (« Toute la France »); it never acts on
 * the job itself: its notification's action only sends the plugin's
 * {@code interrupt} event. Never restarted after the process dies (the job
 * died with the WebView).
 *
 * <p>Started with startForegroundService, it must call startForeground before
 * it stops, or Android crashes the app: every ACTION_START goes foreground
 * first, then stops at once when the plugin asked for a stop meanwhile
 * ({@link #requestStop}).
 */
public class ForegroundRunService extends Service {

    static final String ACTION_START = "re.bruge.herbier.foreground_run.START";
    static final String ACTION_INTERRUPT = "re.bruge.herbier.foreground_run.INTERRUPT";
    static final String EXTRA_GENERATION = "generation";
    // Any id: the app posts no other notification. The channel is the app's
    // downloads channel, the only job the service runs.
    static final int NOTIFICATION_ID = 1;
    static final String CHANNEL_ID = "downloads";
    private static final String LOG = "HerbierForegroundRun";

    /** What the notification shows; immutable. */
    static final class Notice {

        final String title;
        final String text; // nullable
        final int value;
        final int max;
        final String action; // nullable: no action

        Notice(String title, String text, int value, int max, String action) {
            this.title = title;
            this.text = text;
            this.value = value;
            this.max = max;
            this.action = action;
        }
    }

    /** The plugin's latest notice; read here when the service starts. */
    static volatile Notice current;

    // Guarded by ForegroundRunService.class: the plugin's stop and this
    // service's start see each other's write, so one of them stops it.
    /** startForeground was called and onDestroy has not run. */
    private static boolean foreground;
    /** A stop came before the service went foreground. */
    private static boolean stopRequested;

    /** The plugin's start of a service run: a former stop no longer applies. */
    static synchronized void clearStop() {
        stopRequested = false;
    }

    /** True when the service is foreground: the caller stops it; else it stops itself once foreground. */
    static synchronized boolean requestStop() {
        stopRequested = true;
        return foreground;
    }

    /** Posts [notice] while the service is foreground, so nothing is left behind it. */
    @SuppressLint("MissingPermission")
    static synchronized void post(Context ctx, Notice notice) {
        NotificationManagerCompat manager = NotificationManagerCompat.from(ctx);
        if (!foreground || !manager.areNotificationsEnabled()) {
            return;
        }
        try {
            manager.notify(NOTIFICATION_ID, build(ctx, notice));
        } catch (SecurityException e) {
            Log.w(LOG, "notify refused");
        }
    }

    /** The plugin's generation this instance last started for. */
    private int generation;

    static void ensureChannel(Context ctx) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) {
            return;
        }
        NotificationManager manager = ctx.getSystemService(NotificationManager.class);
        if (manager == null || manager.getNotificationChannel(CHANNEL_ID) != null) {
            return;
        }
        manager.createNotificationChannel(
            new NotificationChannel(
                CHANNEL_ID,
                ctx.getString(R.string.foreground_run_channel),
                NotificationManager.IMPORTANCE_LOW
            )
        );
    }

    static Notification build(Context ctx, Notice notice) {
        // A plain open of the app: the activity's own intent is MAIN, so a
        // VIEW or SEND already handled is never replayed.
        Intent open = new Intent(ctx, MainActivity.class)
            .setAction(Intent.ACTION_MAIN)
            .addCategory(Intent.CATEGORY_LAUNCHER)
            .addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP);
        PendingIntent content = PendingIntent.getActivity(ctx, 0, open, PendingIntent.FLAG_IMMUTABLE);
        NotificationCompat.Builder builder = new NotificationCompat.Builder(ctx, CHANNEL_ID)
            .setSmallIcon(R.drawable.ic_launcher_monochrome)
            .setContentTitle(notice.title)
            .setProgress(notice.max, notice.value, false)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setSilent(true)
            .setCategory(NotificationCompat.CATEGORY_PROGRESS)
            // Android 12+ otherwise delays a service's notification by 10 s.
            .setForegroundServiceBehavior(NotificationCompat.FOREGROUND_SERVICE_IMMEDIATE)
            .setContentIntent(content);
        if (notice.text != null) {
            builder.setContentText(notice.text);
        }
        if (notice.action != null) {
            Intent interrupt = new Intent(ctx, ForegroundRunService.class).setAction(ACTION_INTERRUPT);
            PendingIntent pending = PendingIntent.getService(
                ctx,
                0,
                interrupt,
                PendingIntent.FLAG_IMMUTABLE | PendingIntent.FLAG_UPDATE_CURRENT
            );
            builder.addAction(0, notice.action, pending);
        }
        return builder.build();
    }

    @Override
    public int onStartCommand(Intent intent, int flags, int startId) {
        String action = intent == null ? null : intent.getAction();
        if (ACTION_START.equals(action)) {
            generation = intent.getIntExtra(EXTRA_GENERATION, 0);
            Notice notice = current;
            if (notice == null) {
                // Only a start redelivered to a new process: go foreground
                // anyway, then stop.
                notice = new Notice(getString(R.string.foreground_run_channel), null, 0, 0, null);
                requestStop();
            }
            ensureChannel(this);
            int type = Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q ? ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC : 0;
            try {
                ServiceCompat.startForeground(this, NOTIFICATION_ID, build(this, notice), type);
            } catch (IllegalStateException | SecurityException e) {
                // ForegroundServiceStartNotAllowedException (dataSync's budget
                // spent, the app in the background): the job goes on in the
                // foreground only.
                Log.w(LOG, "foreground refused: " + e.getClass().getSimpleName());
                stopSelf();
                return START_NOT_STICKY;
            }
            boolean stop;
            synchronized (ForegroundRunService.class) {
                foreground = true;
                stop = stopRequested;
            }
            Log.i(LOG, "start");
            if (stop) {
                Log.i(LOG, "stopped before start");
                stopSelf();
            }
        } else if (ACTION_INTERRUPT.equals(action)) {
            Log.i(LOG, "interrupt");
            if (!ForegroundRunPlugin.interrupt("user")) {
                stopSelf();
            }
        }
        return START_NOT_STICKY;
    }

    // Android 15+: dataSync's time budget is spent; the service must stop
    // within seconds. The job is cancelled like « Interrompre ».
    @Override
    public void onTimeout(int startId, int fgsType) {
        Log.i(LOG, "timeout");
        ForegroundRunPlugin.interrupt("timeout");
        stopSelf();
    }

    @Override
    public void onDestroy() {
        Log.i(LOG, "destroy");
        synchronized (ForegroundRunService.class) {
            foreground = false;
        }
        ServiceCompat.stopForeground(this, ServiceCompat.STOP_FOREGROUND_REMOVE);
        ForegroundRunPlugin.serviceEnded(generation);
        super.onDestroy();
    }

    @Override
    public IBinder onBind(Intent intent) {
        return null;
    }
}
