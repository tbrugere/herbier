package re.bruge.herbier;

import android.content.Context;
import android.content.pm.ApplicationInfo;
import android.os.Handler;
import android.os.Looper;
import androidx.lifecycle.LiveData;
import androidx.lifecycle.Observer;
import androidx.work.BackoffPolicy;
import androidx.work.Constraints;
import androidx.work.Data;
import androidx.work.ExistingWorkPolicy;
import androidx.work.NetworkType;
import androidx.work.OneTimeWorkRequest;
import androidx.work.WorkInfo;
import androidx.work.WorkManager;
import com.getcapacitor.JSArray;
import com.getcapacitor.JSObject;
import com.getcapacitor.Plugin;
import com.getcapacitor.PluginCall;
import com.getcapacitor.PluginMethod;
import com.getcapacitor.annotation.CapacitorPlugin;
import java.io.File;
import java.io.IOException;
import java.net.URI;
import java.net.URISyntaxException;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Set;
import java.util.concurrent.ExecutionException;
import java.util.concurrent.TimeUnit;
import java.util.regex.Pattern;

/**
 * Herbier's originals' uploads (architecture §5; bound by
 * app/bindings/cap_uploader.ml): one WorkManager job per file, run by
 * {@link UploadWorker}, which PUTs the file to a Drive resumable session URL
 * under a network constraint (UNMETERED for « Envoyer seulement en Wi-Fi »).
 * Jobs survive the app being swiped away. The session URL is a credential: it
 * is never logged. Rejection codes and the {@code jobs} shape are read by the
 * binding: keep them in step.
 */
@CapacitorPlugin(name = "Uploader")
public class UploaderPlugin extends Plugin {

    static final String TAG_ALL = "herbier-original";
    static final String TAG_ID = "herbier-original:";
    private static final String WORK_PREFIX = "original-";
    private static final String DRIVE_SESSIONS = "https://www.googleapis.com/upload/drive/v3/files?";
    private static final Pattern ID = Pattern.compile("[A-Za-z0-9-]+");

    private LiveData<List<WorkInfo>> live;
    private Observer<List<WorkInfo>> observer;

    @Override
    public void load() {
        live = WorkManager.getInstance(getContext()).getWorkInfosByTagLiveData(TAG_ALL);
        observer = infos -> notifyListeners("jobsChanged", new JSObject());
        new Handler(Looper.getMainLooper()).post(() -> live.observeForever(observer));
    }

    @Override
    protected void handleOnDestroy() {
        LiveData<List<WorkInfo>> l = live;
        Observer<List<WorkInfo>> o = observer;
        if (l != null && o != null) {
            new Handler(Looper.getMainLooper()).post(() -> l.removeObserver(o));
        }
        super.handleOnDestroy();
    }

    private boolean debuggable() {
        return (getContext().getApplicationInfo().flags & ApplicationInfo.FLAG_DEBUGGABLE) != 0;
    }

    private boolean allowed(String url) {
        if (url.startsWith(DRIVE_SESSIONS)) {
            return true;
        }
        return debuggable() && debugSink(url);
    }

    // scripts/upload-sink.mjs through adb reverse, debug builds only: plain
    // http to localhost or 127.0.0.1, parsed so that no user info
    // (http://localhost:@other.host) can point it elsewhere.
    private static boolean debugSink(String url) {
        try {
            URI u = new URI(url);
            String host = u.getHost();
            return "http".equals(u.getScheme())
                && u.getRawUserInfo() == null
                && ("localhost".equals(host) || "127.0.0.1".equals(host));
        } catch (URISyntaxException e) {
            return false;
        }
    }

    private static boolean validId(String id) {
        return id != null && ID.matcher(id).matches();
    }

    /** The file at {@code path} under the files directory, or null when the path could leave it. */
    static File underFilesDir(Context context, String path) {
        if (path == null || path.isEmpty() || path.startsWith("/")) {
            return null;
        }
        try {
            File dir = context.getFilesDir().getCanonicalFile();
            File file = new File(dir, path).getCanonicalFile();
            return file.getPath().startsWith(dir.getPath() + File.separator) ? file : null;
        } catch (IOException e) {
            return null;
        }
    }

    @PluginMethod
    public void enqueue(PluginCall call) {
        String id = call.getString("id");
        String path = call.getString("path");
        String url = call.getString("url");
        String mime = call.getString("mimeType");
        String network = call.getString("network");
        if (!validId(id)) {
            call.reject("id must be of [A-Za-z0-9-]", "INVALID_ARGUMENT");
            return;
        }
        File file = underFilesDir(getContext(), path);
        if (file == null) {
            call.reject("path must stay in the files directory", "INVALID_ARGUMENT");
            return;
        }
        if (url == null || !allowed(url)) {
            call.reject("url not allowed", "INVALID_ARGUMENT");
            return;
        }
        if (mime == null || mime.isEmpty()) {
            call.reject("mimeType required", "INVALID_ARGUMENT");
            return;
        }
        NetworkType type;
        if ("unmetered".equals(network)) {
            type = NetworkType.UNMETERED;
        } else if ("connected".equals(network)) {
            type = NetworkType.CONNECTED;
        } else {
            call.reject("network must be connected or unmetered", "INVALID_ARGUMENT");
            return;
        }
        if (!file.isFile()) {
            call.reject("no file at path", "FILE_NOT_FOUND");
            return;
        }
        Data input = new Data.Builder()
            .putString(UploadWorker.ID, id)
            .putString(UploadWorker.PATH, path)
            .putString(UploadWorker.URL, url)
            .putString(UploadWorker.MIME, mime)
            .build();
        OneTimeWorkRequest request = new OneTimeWorkRequest.Builder(UploadWorker.class)
            .setInputData(input)
            .setConstraints(new Constraints.Builder().setRequiredNetworkType(type).build())
            .setBackoffCriteria(BackoffPolicy.EXPONENTIAL, 30, TimeUnit.SECONDS)
            .addTag(TAG_ALL)
            .addTag(TAG_ID + id)
            .build();
        // REPLACE: the new job resumes the session where the old one stopped
        // (its first run asks the session what it holds).
        WorkManager.getInstance(getContext()).enqueueUniqueWork(WORK_PREFIX + id, ExistingWorkPolicy.REPLACE, request);
        call.resolve();
    }

    private static String idOf(WorkInfo info) {
        for (String tag : info.getTags()) {
            if (tag.startsWith(TAG_ID)) {
                return tag.substring(TAG_ID.length());
            }
        }
        return null;
    }

    // The current job of a unique work: REPLACE leaves at most one live one.
    private static WorkInfo current(List<WorkInfo> infos) {
        for (WorkInfo info : infos) {
            if (info.getState() != WorkInfo.State.CANCELLED) {
                return info;
            }
        }
        return infos.isEmpty() ? null : infos.get(0);
    }

    private static JSObject entry(String id, WorkInfo info) {
        JSObject o = new JSObject();
        o.put("id", id);
        o.put("state", info.getState().name());
        o.put("attempts", info.getRunAttemptCount());
        Data out = info.getOutputData();
        int status = out.getInt(UploadWorker.HTTP_STATUS, -1);
        if (status >= 0) {
            o.put("httpStatus", status);
        }
        String body = out.getString(UploadWorker.BODY);
        if (body != null) {
            o.put("body", body);
        }
        String error = out.getString(UploadWorker.ERROR);
        if (error != null) {
            o.put("error", error);
        }
        String message = out.getString(UploadWorker.MESSAGE);
        if (message != null) {
            o.put("message", message);
        }
        return o;
    }

    // Plugin methods run on the plugin's own thread: blocking on WorkManager's
    // futures does not block the UI.
    @PluginMethod
    public void jobs(PluginCall call) {
        WorkManager wm = WorkManager.getInstance(getContext());
        try {
            Set<String> ids = new LinkedHashSet<>();
            for (WorkInfo info : wm.getWorkInfosByTag(TAG_ALL).get()) {
                String id = idOf(info);
                if (id != null) {
                    ids.add(id);
                }
            }
            JSArray jobs = new JSArray();
            for (String id : ids) {
                WorkInfo info = current(wm.getWorkInfosForUniqueWork(WORK_PREFIX + id).get());
                if (info != null) {
                    jobs.put(entry(id, info));
                }
            }
            JSObject result = new JSObject();
            result.put("jobs", jobs);
            call.resolve(result);
        } catch (ExecutionException e) {
            call.reject("WorkManager: " + e.getMessage(), "WORK_MANAGER");
        } catch (InterruptedException e) {
            Thread.currentThread().interrupt();
            call.reject("interrupted", "WORK_MANAGER");
        }
    }

    @PluginMethod
    public void cancel(PluginCall call) {
        String id = call.getString("id");
        if (!validId(id)) {
            call.reject("id must be of [A-Za-z0-9-]", "INVALID_ARGUMENT");
            return;
        }
        WorkManager.getInstance(getContext()).cancelUniqueWork(WORK_PREFIX + id);
        call.resolve();
    }
}
