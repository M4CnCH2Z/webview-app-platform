# Keep default rules; add WebView bridge exposure minimal
-keepclassmembers class io.m4cnch2z.app.WebViewActivity$* {
    @android.webkit.JavascriptInterface <methods>;
}
