package re.bruge.herbier;

import android.content.Context;
import android.util.Log;
import androidx.annotation.NonNull;
import androidx.work.Data;
import androidx.work.Worker;
import androidx.work.WorkerParameters;
import java.io.File;
import java.io.FileInputStream;
import java.io.IOException;
import java.io.InputStream;
import java.io.InputStreamReader;
import java.io.OutputStream;
import java.io.Reader;
import java.net.HttpURLConnection;
import java.net.URI;
import java.nio.charset.StandardCharsets;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

/**
 * One original's bytes PUT to a Drive resumable session (architecture §5).
 * Every run first asks the session how much it holds ({@code
 * Content-Range: bytes *}{@code /N}) and sends the rest: a job that replaced
 * another starts again at run 0 while its session may already hold bytes, or
 * the whole file. 200/201 succeed with
 * Drive's file JSON; 404/410 (session gone) and other final 4xx fail with the
 * answer; IO errors, 308 (incomplete), 408, 429 and 5xx retry with
 * WorkManager's backoff, at most {@link #MAX_RUNS} runs. No foreground service:
 * a photo fits WorkManager's 10-minute window, and an interrupted run resumes.
 * A stopped job (cancelled, replaced) stops sending. Any unexpected exception
 * fails the job as GAVE_UP, never with empty output. The URL is a credential:
 * never logged, nor any exception message (one may quote it).
 */
public class UploadWorker extends Worker {

    static final String ID = "id";
    static final String PATH = "path";
    static final String URL = "url";
    static final String MIME = "mime";
    static final String HTTP_STATUS = "httpStatus";
    static final String BODY = "body";
    static final String ERROR = "error";
    static final String MESSAGE = "message";

    private static final String TAG = "HerbierUpload";
    private static final int MAX_RUNS = 10;
    // Chars: at most 3 bytes each in Data's serialized form (modified UTF-8),
    // which must stay under Data.MAX_DATA_BYTES (10 240).
    private static final int MAX_BODY = 3000;
    private static final Pattern RANGE = Pattern.compile("bytes=0-(\\d+)");

    public UploadWorker(@NonNull Context context, @NonNull WorkerParameters params) {
        super(context, params);
    }

    private static final class Answer {

        final int status;
        final String body;
        final String range;

        Answer(int status, String body, String range) {
            this.status = status;
            this.body = body;
            this.range = range;
        }
    }

    @NonNull
    @Override
    public Result doWork() {
        String id = getInputData().getString(ID);
        String path = getInputData().getString(PATH);
        String url = getInputData().getString(URL);
        String mime = getInputData().getString(MIME);
        File file = UploaderPlugin.underFilesDir(getApplicationContext(), path);
        if (file == null || !file.isFile() || !file.canRead()) {
            Log.i(TAG, id + " file missing");
            return Result.failure(new Data.Builder().putString(ERROR, "FILE_NOT_FOUND").build());
        }
        if (url == null || mime == null) {
            Log.i(TAG, id + " bad input");
            return gaveUp(id, "bad input");
        }
        long size = file.length();
        try {
            Answer held = send(url, file, size, -1, mime);
            Log.i(TAG, id + " status query " + held.status);
            if (held.status != 308) {
                return outcome(id, held);
            }
            long offset = received(held.range);
            if (offset >= size) {
                return retryOr(id, "incomplete upload");
            }
            Answer answer = send(url, file, size, offset, mime);
            Log.i(TAG, id + " " + answer.status);
            return outcome(id, answer);
        } catch (IOException e) {
            Log.i(TAG, id + " " + e.getClass().getSimpleName());
            return retryOr(id, e.getClass().getSimpleName());
        } catch (RuntimeException e) {
            Log.w(TAG, id + " " + e.getClass().getSimpleName());
            return gaveUp(id, e.getClass().getSimpleName());
        }
    }

    // Bytes the session holds, from a 308's Range (none: nothing yet).
    private static long received(String range) {
        if (range == null) {
            return 0;
        }
        Matcher m = RANGE.matcher(range);
        return m.find() ? Long.parseLong(m.group(1)) + 1 : 0;
    }

    private Result outcome(String id, Answer a) {
        if (a.status == 200 || a.status == 201) {
            return Result.success(answerData(a));
        }
        if (a.status == 308) {
            return retryOr(id, "incomplete upload");
        }
        if (a.status == 408 || a.status == 429 || a.status >= 500) {
            return retryOr(id, "HTTP " + a.status);
        }
        return Result.failure(answerData(a));
    }

    private static Data answerData(Answer a) {
        return new Data.Builder().putInt(HTTP_STATUS, a.status).putString(BODY, a.body).build();
    }

    private Result retryOr(String id, String message) {
        if (getRunAttemptCount() < MAX_RUNS - 1) {
            return Result.retry();
        }
        return gaveUp(id, message);
    }

    private static Result gaveUp(String id, String message) {
        Log.i(TAG, id + " gave up");
        return Result.failure(new Data.Builder().putString(ERROR, "GAVE_UP").putString(MESSAGE, message).build());
    }

    // offset < 0: the status query (no body); else the bytes from offset.
    private Answer send(String url, File file, long size, long offset, String mime) throws IOException {
        HttpURLConnection c = (HttpURLConnection) URI.create(url).toURL().openConnection();
        try {
            c.setInstanceFollowRedirects(false);
            c.setConnectTimeout(30_000);
            c.setReadTimeout(120_000);
            c.setRequestMethod("PUT");
            c.setDoOutput(true);
            if (offset < 0) {
                c.setRequestProperty("Content-Range", "bytes */" + size);
                c.setFixedLengthStreamingMode(0L);
                c.getOutputStream().close();
            } else {
                c.setRequestProperty("Content-Type", mime);
                if (offset > 0) {
                    c.setRequestProperty("Content-Range", "bytes " + offset + "-" + (size - 1) + "/" + size);
                }
                c.setFixedLengthStreamingMode(size - offset);
                try (InputStream in = new FileInputStream(file); OutputStream out = c.getOutputStream()) {
                    skipFully(in, offset);
                    byte[] buffer = new byte[64 * 1024];
                    int n;
                    while ((n = in.read(buffer)) != -1) {
                        if (isStopped()) {
                            throw new IOException("stopped");
                        }
                        out.write(buffer, 0, n);
                    }
                }
            }
            int status = c.getResponseCode();
            InputStream stream = status >= 400 ? c.getErrorStream() : c.getInputStream();
            return new Answer(status, read(stream), c.getHeaderField("Range"));
        } finally {
            c.disconnect();
        }
    }

    private static void skipFully(InputStream in, long n) throws IOException {
        long left = n;
        while (left > 0) {
            long skipped = in.skip(left);
            if (skipped <= 0) {
                throw new IOException("file shorter than the session's offset");
            }
            left -= skipped;
        }
    }

    private static String read(InputStream stream) throws IOException {
        if (stream == null) {
            return "";
        }
        StringBuilder b = new StringBuilder();
        try (Reader r = new InputStreamReader(stream, StandardCharsets.UTF_8)) {
            char[] buffer = new char[1024];
            int n;
            while (b.length() < MAX_BODY && (n = r.read(buffer)) != -1) {
                b.append(buffer, 0, n);
            }
        }
        return b.length() > MAX_BODY ? b.substring(0, MAX_BODY) : b.toString();
    }
}
