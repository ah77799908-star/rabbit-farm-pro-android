#!/usr/bin/env bash
# Rabbit Farm Pro - Android shell (WebView of the live site + daily 9:00 reminders).
# Build: needs JDK 17, Android SDK (platforms;android-34, build-tools;34.0.0), python3, curl.
#   ANDROID_HOME=/path/to/sdk ./build.sh
# Signing key: NEVER commit it. Set KS (keystore path), KS_PASS (password), KS_ALIAS (default rf).
# If KS does not exist it is created. Updates must be signed with the same key.
set -euo pipefail
: "${ANDROID_HOME:?set ANDROID_HOME}"; : "${KS:?set KS to keystore path}"; : "${KS_PASS:?set KS_PASS}"
ALIAS="${KS_ALIAS:-rf}"
BT="$ANDROID_HOME/build-tools/34.0.0"; AJ="$ANDROID_HOME/platforms/android-34/android.jar"
W="$(pwd)/build-out"; rm -rf "$W"; S="$W/app"
mkdir -p "$S/src/com/rabbitfarm/pro" "$S/res/mipmap-xxxhdpi" "$S/res/values" "$W/gen" "$W/cls"
# icon is taken from the live app's manifest
python3 - "$S" <<'PY'
import json,base64,sys,urllib.request
m=json.load(urllib.request.urlopen('https://ah77799908-star.github.io/rabbit-farm-pro/manifest.webmanifest'))
i=[x for x in m['icons'] if x['sizes']=='512x512'] or m['icons']
open(sys.argv[1]+'/res/mipmap-xxxhdpi/ic_launcher.png','wb').write(base64.b64decode(i[0]['src'].split(',')[1]))
PY
cat > "$S/AndroidManifest.xml" <<'EOF'
<?xml version="1.0" encoding="utf-8"?>
<manifest xmlns:android="http://schemas.android.com/apk/res/android" package="com.rabbitfarm.pro" android:versionCode="1" android:versionName="1.0">
  <uses-sdk android:minSdkVersion="29" android:targetSdkVersion="34"/>
  <uses-permission android:name="android.permission.INTERNET"/>
  <uses-permission android:name="android.permission.POST_NOTIFICATIONS"/>
  <uses-permission android:name="android.permission.RECEIVE_BOOT_COMPLETED"/>
  <application android:label="مزرعة الأرانب" android:icon="@mipmap/ic_launcher" android:allowBackup="true" android:usesCleartextTraffic="false" android:theme="@style/AppTheme">
    <activity android:name=".MainActivity" android:exported="true" android:configChanges="orientation|screenSize|keyboardHidden|screenLayout|uiMode" android:windowSoftInputMode="adjustResize">
      <intent-filter><action android:name="android.intent.action.MAIN"/><category android:name="android.intent.category.LAUNCHER"/></intent-filter>
    </activity>
    <receiver android:name=".AlarmReceiver" android:exported="false"/>
    <receiver android:name=".BootReceiver" android:exported="true">
      <intent-filter><action android:name="android.intent.action.BOOT_COMPLETED"/><action android:name="android.intent.action.MY_PACKAGE_REPLACED"/></intent-filter>
    </receiver>
  </application>
</manifest>
EOF
cat > "$S/res/values/styles.xml" <<'EOF'
<resources><style name="AppTheme" parent="android:Theme.DeviceDefault.Light.NoActionBar"><item name="android:statusBarColor">#2f6b4f</item><item name="android:windowBackground">@android:color/white</item></style></resources>
EOF
P="$S/src/com/rabbitfarm/pro"
cat > "$P/Sched.java" <<'EOF'
package com.rabbitfarm.pro;
import android.app.*;
import android.content.*;
import org.json.*;
public class Sched {
  static final String CH = "alerts";
  static void channel(Context c) {
    NotificationManager nm = (NotificationManager) c.getSystemService(Context.NOTIFICATION_SERVICE);
    nm.createNotificationChannel(new NotificationChannel(CH, "تنبيهات المزرعة", NotificationManager.IMPORTANCE_HIGH));
  }
  static void apply(Context c, String json) {
    try {
      SharedPreferences sp = c.getSharedPreferences("s", 0);
      AlarmManager am = (AlarmManager) c.getSystemService(Context.ALARM_SERVICE);
      int old = sp.getInt("n", 0);
      for (int i = 0; i < old; i++) am.cancel(pi(c, i, "", ""));
      sp.edit().putString("list", json).apply();
      JSONArray a = new JSONArray(json);
      long now = System.currentTimeMillis();
      int n = 0;
      for (int i = 0; i < a.length() && i < 60; i++) {
        JSONObject o = a.getJSONObject(i);
        long t = o.getLong("t");
        if (t <= now) continue;
        am.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, t, pi(c, i, o.getString("title"), o.getString("body")));
        n = i + 1;
      }
      sp.edit().putInt("n", Math.max(n, a.length())).apply();
    } catch (Exception e) { }
  }
  static void restore(Context c) {
    String j = c.getSharedPreferences("s", 0).getString("list", null);
    if (j != null) apply(c, j);
  }
  static PendingIntent pi(Context c, int i, String title, String body) {
    Intent in = new Intent(c, AlarmReceiver.class).putExtra("title", title).putExtra("body", body).putExtra("id", i);
    return PendingIntent.getBroadcast(c, i, in, PendingIntent.FLAG_UPDATE_CURRENT | PendingIntent.FLAG_IMMUTABLE);
  }
}
EOF
cat > "$P/AlarmReceiver.java" <<'EOF'
package com.rabbitfarm.pro;
import android.app.*;
import android.content.*;
public class AlarmReceiver extends BroadcastReceiver {
  public void onReceive(Context c, Intent in) {
    Sched.channel(c);
    PendingIntent open = PendingIntent.getActivity(c, 0, new Intent(c, MainActivity.class), PendingIntent.FLAG_IMMUTABLE | PendingIntent.FLAG_UPDATE_CURRENT);
    String body = in.getStringExtra("body");
    Notification n = new Notification.Builder(c, Sched.CH).setSmallIcon(android.R.drawable.stat_notify_more)
      .setContentTitle(in.getStringExtra("title")).setContentText(body.split("\n")[0])
      .setStyle(new Notification.BigTextStyle().bigText(body)).setContentIntent(open).setAutoCancel(true).build();
    ((NotificationManager) c.getSystemService(Context.NOTIFICATION_SERVICE)).notify(1000 + in.getIntExtra("id", 0), n);
  }
}
EOF
cat > "$P/BootReceiver.java" <<'EOF'
package com.rabbitfarm.pro;
import android.content.*;
public class BootReceiver extends BroadcastReceiver {
  public void onReceive(Context c, Intent in) { Sched.restore(c); }
}
EOF
cat > "$P/MainActivity.java" <<'EOF'
package com.rabbitfarm.pro;
import android.app.Activity;
import android.content.*;
import android.net.Uri;
import android.os.*;
import android.provider.MediaStore;
import android.util.Base64;
import android.view.WindowManager;
import android.webkit.*;
import android.widget.Toast;
import java.io.OutputStream;

public class MainActivity extends Activity {
  static final String URL = "https://ah77799908-star.github.io/rabbit-farm-pro/";
  WebView w;
  ValueCallback<Uri[]> fileCb;
  static final String JS =
    "(function(){if(window.__rfn)return;window.__rfn=1;var last='';function run(){try{" +
    "if(!window.Core||!window.Android)return;var raw=localStorage.getItem('rabbitpro.v1');if(!raw||raw===last)return;last=raw;" +
    "var S=(window.Store&&Store.S)||JSON.parse(raw);var out=[],now=new Date();" +
    "for(var i=0;i<30;i++){var d=new Date(now.getFullYear(),now.getMonth(),now.getDate()+i,9,0,0);if(d<=now)continue;" +
    "var A=Core.alerts(S,Core.today(d));if(!A.length)continue;var L=A.slice(0,6).map(function(a){return a.i+' '+a.txt});" +
    "if(A.length>6)L.push('+ '+(A.length-6)+' تنبيه آخر');" +
    "out.push({t:d.getTime(),title:'مزرعة الأرانب 🐇 ('+A.length+' تنبيه)',body:L.join('\\n')});}" +
    "Android.schedule(JSON.stringify(out));}catch(e){}}" +
    "run();setInterval(run,20000);document.addEventListener('visibilitychange',function(){last='';run()});})();";

  protected void onCreate(Bundle b) {
    super.onCreate(b);
    Sched.channel(this);
    if (Build.VERSION.SDK_INT >= 33 && checkSelfPermission("android.permission.POST_NOTIFICATIONS") != 0)
      requestPermissions(new String[]{"android.permission.POST_NOTIFICATIONS"}, 1);
    w = new WebView(this);
    setContentView(w);
    WebSettings s = w.getSettings();
    s.setJavaScriptEnabled(true); s.setDomStorageEnabled(true); s.setAllowFileAccess(false);
    s.setCacheMode(WebSettings.LOAD_DEFAULT);
    w.addJavascriptInterface(new Object() {
      @JavascriptInterface public void schedule(String json) { Sched.apply(getApplicationContext(), json); }
      @JavascriptInterface public void saveFile(String name, String mime, String b64) { save(name, mime, b64); }
    }, "Android");
    w.setWebViewClient(new WebViewClient() {
      public boolean shouldOverrideUrlLoading(WebView v, WebResourceRequest r) {
        Uri u = r.getUrl();
        if ("ah77799908-star.github.io".equals(u.getHost())) return false;
        try { startActivity(new Intent(Intent.ACTION_VIEW, u)); } catch (Exception e) { }
        return true;
      }
      public void onPageFinished(WebView v, String url) { v.evaluateJavascript(JS, null); }
    });
    w.setWebChromeClient(new WebChromeClient() {
      public boolean onShowFileChooser(WebView v, ValueCallback<Uri[]> cb, FileChooserParams p) {
        if (fileCb != null) fileCb.onReceiveValue(null);
        fileCb = cb;
        Intent i = new Intent(Intent.ACTION_GET_CONTENT).addCategory(Intent.CATEGORY_OPENABLE).setType("*/*");
        try { startActivityForResult(Intent.createChooser(i, "اختر الملف"), 7); } catch (Exception e) { fileCb = null; return false; }
        return true;
      }
    });
    w.setDownloadListener(new DownloadListener() {
      public void onDownloadStart(String url, String ua, String cd, String mime, long len) {
        if (!url.startsWith("blob:")) { try { startActivity(new Intent(Intent.ACTION_VIEW, Uri.parse(url))); } catch (Exception e) { } return; }
        String name = URLUtil.guessFileName(url, cd, mime);
        String js = "fetch('" + url + "').then(function(r){return r.blob()}).then(function(b){var f=new FileReader();f.onload=function(){Android.saveFile(" +
          JSONObjectQuote(name) + "," + JSONObjectQuote(mime == null ? "application/octet-stream" : mime) + ",f.result.split(',')[1])};f.readAsDataURL(b)})";
        w.evaluateJavascript(js, null);
      }
    });
    w.loadUrl(URL);
  }
  static String JSONObjectQuote(String s) { return org.json.JSONObject.quote(s); }
  void save(String name, String mime, String b64) {
    try {
      ContentValues v = new ContentValues();
      v.put(MediaStore.Downloads.DISPLAY_NAME, name);
      v.put(MediaStore.Downloads.MIME_TYPE, mime);
      Uri u = getContentResolver().insert(MediaStore.Downloads.EXTERNAL_CONTENT_URI, v);
      OutputStream o = getContentResolver().openOutputStream(u);
      o.write(Base64.decode(b64, Base64.DEFAULT)); o.close();
      runOnUiThread(() -> Toast.makeText(this, "تم الحفظ في مجلد التنزيلات: " + name, Toast.LENGTH_LONG).show());
    } catch (Exception e) {
      runOnUiThread(() -> Toast.makeText(this, "تعذر حفظ الملف", Toast.LENGTH_LONG).show());
    }
  }
  protected void onActivityResult(int rq, int rs, Intent d) {
    if (rq == 7 && fileCb != null) {
      Uri[] r = (rs == RESULT_OK && d != null && d.getData() != null) ? new Uri[]{d.getData()} : null;
      fileCb.onReceiveValue(r); fileCb = null;
    }
  }
  public void onBackPressed() { if (w.canGoBack()) w.goBack(); else super.onBackPressed(); }
}
EOF
"$BT/aapt2" compile --dir "$S/res" -o "$W/res.zip"
"$BT/aapt2" link -o "$W/base.apk" -I "$AJ" --manifest "$S/AndroidManifest.xml" --java "$W/gen" "$W/res.zip" --min-sdk-version 29 --target-sdk-version 34
javac -encoding UTF-8 -source 8 -target 8 -cp "$AJ" -d "$W/cls" $(find "$S/src" "$W/gen" -name '*.java')
"$BT/d8" --lib "$AJ" --min-api 29 --output "$W" $(find "$W/cls" -name '*.class')
cp "$W/base.apk" "$W/un.apk"; (cd "$W" && zip -q un.apk classes.dex)
"$BT/zipalign" -f 4 "$W/un.apk" "$W/al.apk"
[ -f "$KS" ] || keytool -genkeypair -keystore "$KS" -alias "$ALIAS" -keyalg RSA -keysize 2048 -validity 10000 -storepass "$KS_PASS" -keypass "$KS_PASS" -dname "CN=Rabbit Farm Pro"
"$BT/apksigner" sign --ks "$KS" --ks-key-alias "$ALIAS" --ks-pass env:KS_PASS --out rabbit-farm-pro.apk "$W/al.apk"
"$BT/apksigner" verify -v rabbit-farm-pro.apk | head -3
echo "built: $(pwd)/rabbit-farm-pro.apk"
