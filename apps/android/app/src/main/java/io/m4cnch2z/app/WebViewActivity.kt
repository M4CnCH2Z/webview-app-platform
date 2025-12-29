package io.m4cnch2z.app

import android.annotation.SuppressLint
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.util.Log
import android.webkit.CookieManager
import android.webkit.JavascriptInterface
import android.webkit.WebChromeClient
import android.webkit.WebResourceRequest
import android.webkit.WebSettings
import android.webkit.WebView
import android.webkit.WebViewClient
import androidx.appcompat.app.AppCompatActivity
import androidx.webkit.JavaScriptReplyProxy
import androidx.webkit.WebMessageCompat
import androidx.webkit.WebViewCompat
import androidx.webkit.WebViewFeature
import io.m4cnch2z.app.BuildConfig
import org.json.JSONObject
import java.util.UUID

class WebViewActivity : AppCompatActivity() {
    private lateinit var webView: WebView
    private val allowlistWithPort: Set<String> = setOf(
        "https://project.sandeul.work",
        "https://app.example.com",
        "http://10.0.2.2:3000",
        "http://localhost:3000"
    )
    private val allowlistHosts: Set<String> = setOf(
        "project.sandeul.work",
        "app.example.com",
        "10.0.2.2",
        "localhost"
    )

    @SuppressLint("SetJavaScriptEnabled")
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        Log.i("WebViewActivity", "test")
        setContentView(R.layout.activity_webview)
        webView = findViewById(R.id.webView)

        CookieManager.getInstance().setAcceptCookie(true)
        CookieManager.getInstance().setAcceptThirdPartyCookies(webView, false)

        val settings: WebSettings = webView.settings
        settings.javaScriptEnabled = true
        settings.domStorageEnabled = true
        settings.allowFileAccess = false
        settings.allowFileAccessFromFileURLs = false
        settings.allowUniversalAccessFromFileURLs = false
        settings.mixedContentMode = WebSettings.MIXED_CONTENT_NEVER_ALLOW
        settings.userAgentString = settings.userAgentString + " WebViewApp/0.1.0"

        if (BuildConfig.DEBUG && Build.VERSION.SDK_INT >= Build.VERSION_CODES.KITKAT) {
            WebView.setWebContentsDebuggingEnabled(true)
        }

        webView.webChromeClient = WebChromeClient()

        webView.webViewClient = object : WebViewClient() {
            override fun shouldOverrideUrlLoading(view: WebView?, request: WebResourceRequest?): Boolean {
                val uri = request?.url ?: return false
                val originWithPort = if (uri.port != -1) {
                    "${uri.scheme}://${uri.host}:${uri.port}"
                } else {
                    "${uri.scheme}://${uri.host}"
                }

                // Allow navigation inside WebView for allowed origins/hosts (handles relative links)
                if (uri.host == null || allowlistWithPort.contains(originWithPort) || allowlistHosts.contains(uri.host)) {
                    view?.loadUrl(uri.toString())
                    return true
                }

                openExternal(uri.toString())
                return true
            }

            // Fallback for older API level calls
            override fun shouldOverrideUrlLoading(view: WebView?, url: String?): Boolean {
                if (url == null) return false
                val uri = Uri.parse(url)
                val originWithPort = if (uri.port != -1) {
                    "${uri.scheme}://${uri.host}:${uri.port}"
                } else {
                    "${uri.scheme}://${uri.host}"
                }
                if (uri.host == null || allowlistWithPort.contains(originWithPort) || allowlistHosts.contains(uri.host)) {
                    view?.loadUrl(url)
                    return true
                }
                openExternal(url)
                return true
            }
        }

        setupBridge()
        webView.loadUrl(resolveInitialUrl())
    }

    private fun resolveInitialUrl(): String {
        val deepLink: Uri? = intent?.data
        if (deepLink != null) {
            val originWithPort = if (deepLink.port != -1) {
                "${deepLink.scheme}://${deepLink.host}:${deepLink.port}"
            } else {
                "${deepLink.scheme}://${deepLink.host}"
            }
            if (allowlistWithPort.contains(originWithPort) || (deepLink.host != null && allowlistHosts.contains(deepLink.host!!))) {
                return deepLink.toString()
            }
        }
        return "https://project.sandeul.work"
    }

    private fun openExternal(url: String) {
        startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(url)))
    }

    private fun setupBridge() {
        if (WebViewFeature.isFeatureSupported(WebViewFeature.WEB_MESSAGE_LISTENER)) {
            val listener = WebViewCompat.WebMessageListener { _: WebView, message: WebMessageCompat, sourceOrigin: Uri, _: Boolean, _: JavaScriptReplyProxy ->
                val origin = sourceOrigin.toString()
                val host = sourceOrigin.host
                if (!(allowlistWithPort.contains(origin) || (host != null && allowlistHosts.contains(host)))) {
                    Log.w("Bridge", "Rejected origin $sourceOrigin")
                    return@WebMessageListener
                }
                val data = message.data ?: return@WebMessageListener
                handleBridgeMessage(data)
            }
            WebViewCompat.addWebMessageListener(
                webView,
                "__nativeBridge",
                allowlistWithPort,
                listener
            )
        } else {
            webView.addJavascriptInterface(object {
                @JavascriptInterface
                fun postMessage(message: String) {
                    handleBridgeMessage(message)
                }
            }, "__nativeBridge")
        }
    }

    private fun handleBridgeMessage(raw: String) {
        try {
            val json = JSONObject(raw)
            val type = json.getString("type")
            val id = json.getString("id")
            when (type) {
                "capabilities.request" -> respond(
                    id = id,
                    ok = true,
                    payload = mapOf(
                        "appVersion" to BuildConfig.VERSION_NAME,
                        "bridgeVersion" to "1.0.0",
                        "supported" to listOf(
                            "auth.getSession",
                            "nav.openExternal",
                            "device.getPushToken",
                            "media.pickImage"
                        )
                    )
                )
                "nav.openExternal" -> {
                    val url = json.getJSONObject("payload").getString("url")
                    openExternal(url)
                    respond(id = id, ok = true, payload = mapOf("opened" to true))
                }
                "auth.getSession" -> {
                    // Placeholder: wire to real session store
                    respond(id = id, ok = true, payload = mapOf("sessionId" to null, "userId" to null))
                }
                "device.getPushToken" -> {
                    // Placeholder token
                    respond(id = id, ok = true, payload = mapOf("token" to UUID.randomUUID().toString()))
                }
                "media.pickImage" -> {
                    respond(
                        id = id,
                        ok = false,
                        error = mapOf("code" to "NOT_SUPPORTED", "message" to "Not implemented")
                    )
                }
                else -> {
                    respond(
                        id = id,
                        ok = false,
                        error = mapOf("code" to "NOT_SUPPORTED", "message" to "Unknown type")
                    )
                }
            }
        } catch (e: Exception) {
            Log.e("Bridge", "Invalid message", e)
        }
    }

    private fun respond(id: String, ok: Boolean, payload: Any? = null, error: Map<String, Any?>? = null) {
        val response = JSONObject()
        response.put("id", id)
        response.put("ok", ok)
        payload?.let { response.put("payload", it) }
        error?.let { response.put("error", JSONObject(it)) }
        val script =
            """
            (function(){
                const event = new MessageEvent('message', { data: '${response.toString()}' });
                window.dispatchEvent(event);
            })();
            """.trimIndent()
        webView.post { webView.evaluateJavascript(script, null) }
    }
}
