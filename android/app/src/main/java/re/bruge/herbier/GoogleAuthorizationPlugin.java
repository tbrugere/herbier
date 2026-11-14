package re.bruge.herbier;

import android.accounts.Account;
import android.app.Activity;
import android.app.PendingIntent;
import android.util.Log;
import androidx.activity.result.ActivityResult;
import androidx.activity.result.ActivityResultLauncher;
import androidx.activity.result.IntentSenderRequest;
import androidx.activity.result.contract.ActivityResultContracts;
import com.getcapacitor.JSArray;
import com.getcapacitor.JSObject;
import com.getcapacitor.Plugin;
import com.getcapacitor.PluginCall;
import com.getcapacitor.PluginMethod;
import com.getcapacitor.annotation.CapacitorPlugin;
import com.google.android.gms.auth.api.identity.AuthorizationClient;
import com.google.android.gms.auth.api.identity.AuthorizationRequest;
import com.google.android.gms.auth.api.identity.AuthorizationResult;
import com.google.android.gms.auth.api.identity.ClearTokenRequest;
import com.google.android.gms.auth.api.identity.Identity;
import com.google.android.gms.common.api.ApiException;
import com.google.android.gms.common.api.CommonStatusCodes;
import com.google.android.gms.common.api.Scope;
import java.util.ArrayList;
import java.util.List;
import org.json.JSONException;

/**
 * Play Services' AuthorizationClient for Herbier's Drive grant (architecture
 * §5, "Drive token"; bound by app/bindings/cap_google_authorization.ml).
 * {@code authorize} hands out the 1-hour access token Play Services caches,
 * silently once the scope is granted, and shows the consent screen only when
 * the call is interactive. {@code clearToken} drops a token Drive refused.
 * Rejection codes are read by app/sync_core/auth/drive_consent.ml: keep them
 * in step. Only the drive.file scope is granted. No log line contains a token.
 */
@CapacitorPlugin(name = "GoogleAuthorization")
public class GoogleAuthorizationPlugin extends Plugin {

    private static final String TAG = "GoogleAuthorization";
    // Equal to Drive_consent.scope (app/sync_core/auth/drive_consent.ml).
    private static final String DRIVE_FILE = "https://www.googleapis.com/auth/drive.file";

    private ActivityResultLauncher<IntentSenderRequest> consent;
    // The interactive call waiting for the consent screen; one at a time.
    private PluginCall pending;
    private List<String> pendingScopes;

    @Override
    public void load() {
        // registerForActivityResult must run before the activity is STARTED;
        // load() runs inside BridgeActivity.onCreate, so it is in time.
        consent = bridge.registerForActivityResult(
            new ActivityResultContracts.StartIntentSenderForResult(),
            this::onConsentResult
        );
    }

    @PluginMethod
    public void authorize(PluginCall call) {
        List<String> scopes = scopesOf(call);
        if (scopes == null || scopes.isEmpty()) {
            call.reject("scopes required", "INVALID_ARGUMENT");
            return;
        }
        for (String s : scopes) {
            if (!DRIVE_FILE.equals(s)) {
                call.reject("only drive.file is granted", "INVALID_ARGUMENT");
                return;
            }
        }
        Activity activity = getActivity();
        if (activity == null) {
            call.reject("no activity", "NO_ACTIVITY");
            return;
        }
        boolean interactive = Boolean.TRUE.equals(call.getBoolean("interactive", false));
        List<Scope> requested = new ArrayList<>();
        for (String s : scopes) {
            requested.add(new Scope(s));
        }
        AuthorizationRequest.Builder builder = AuthorizationRequest.builder().setRequestedScopes(requested);
        String account = call.getString("account");
        if (account != null && !account.isEmpty()) {
            builder.setAccount(new Account(account, "com.google"));
        }
        Identity.getAuthorizationClient(activity)
            .authorize(builder.build())
            .addOnSuccessListener(result -> {
                if (!result.hasResolution()) {
                    settle(call, scopes, result);
                } else if (!interactive) {
                    Log.i(TAG, "authorize: consent needed");
                    call.reject("Drive consent needed", "NEEDS_CONSENT");
                } else {
                    askConsent(call, scopes, result.getPendingIntent());
                }
            })
            .addOnFailureListener(e -> fail(call, e));
    }

    @PluginMethod
    public void clearToken(PluginCall call) {
        String token = call.getString("token");
        if (token == null || token.isEmpty()) {
            call.reject("token required", "INVALID_ARGUMENT");
            return;
        }
        Activity activity = getActivity();
        if (activity == null) {
            call.reject("no activity", "NO_ACTIVITY");
            return;
        }
        Identity.getAuthorizationClient(activity)
            .clearToken(ClearTokenRequest.builder().setToken(token).build())
            .addOnSuccessListener(unused -> {
                Log.i(TAG, "clearToken: ok");
                call.resolve(new JSObject());
            })
            .addOnFailureListener(e -> fail(call, e));
    }

    private static List<String> scopesOf(PluginCall call) {
        JSArray array = call.getArray("scopes");
        if (array == null) {
            return null;
        }
        try {
            return array.<String>toList();
        } catch (JSONException e) {
            return null;
        }
    }

    private void askConsent(PluginCall call, List<String> scopes, PendingIntent intent) {
        if (pending != null) {
            call.reject("an authorization is already showing", "BUSY");
            return;
        }
        if (intent == null) {
            call.reject("no consent intent", "AUTHORIZATION_FAILED");
            return;
        }
        pending = call;
        pendingScopes = scopes;
        Log.i(TAG, "authorize: showing consent");
        consent.launch(new IntentSenderRequest.Builder(intent.getIntentSender()).build());
    }

    private void onConsentResult(ActivityResult activityResult) {
        PluginCall call = pending;
        List<String> scopes = pendingScopes;
        pending = null;
        pendingScopes = null;
        if (call == null) {
            return;
        }
        if (activityResult.getResultCode() != Activity.RESULT_OK) {
            Log.i(TAG, "authorize: consent dismissed");
            call.reject("consent dismissed", "USER_CANCELLED");
            return;
        }
        Activity activity = getActivity();
        if (activity == null) {
            call.reject("no activity", "NO_ACTIVITY");
            return;
        }
        AuthorizationClient client = Identity.getAuthorizationClient(activity);
        try {
            settle(call, scopes, client.getAuthorizationResultFromIntent(activityResult.getData()));
        } catch (ApiException e) {
            fail(call, e);
        }
    }

    private void settle(PluginCall call, List<String> scopes, AuthorizationResult result) {
        List<String> granted = result.getGrantedScopes();
        if (granted == null || !granted.containsAll(scopes)) {
            Log.i(TAG, "authorize: scope not granted");
            call.reject("scope not granted", "SCOPE_NOT_GRANTED");
            return;
        }
        String token = result.getAccessToken();
        if (token == null) {
            call.reject("no access token", "AUTHORIZATION_FAILED");
            return;
        }
        JSObject answer = new JSObject();
        answer.put("accessToken", token);
        answer.put("grantedScopes", new JSArray(granted));
        Log.i(TAG, "authorize: ok");
        call.resolve(answer);
    }

    private static void fail(PluginCall call, Exception e) {
        String code = "AUTHORIZATION_FAILED";
        String message = String.valueOf(e.getMessage());
        if (e instanceof ApiException) {
            int status = ((ApiException) e).getStatusCode();
            message = "status " + status + ": " + message;
            code = codeOf(status);
        }
        Log.w(TAG, "failed: " + message);
        call.reject(message, code);
    }

    // The statuses a caller acts on; any other is AUTHORIZATION_FAILED.
    private static String codeOf(int status) {
        switch (status) {
            case CommonStatusCodes.NETWORK_ERROR:
                return "NETWORK_ERROR";
            case CommonStatusCodes.DEVELOPER_ERROR:
                return "DEVELOPER_ERROR";
            case CommonStatusCodes.SIGN_IN_REQUIRED:
                return "SIGN_IN_REQUIRED";
            default:
                return "AUTHORIZATION_FAILED";
        }
    }
}
