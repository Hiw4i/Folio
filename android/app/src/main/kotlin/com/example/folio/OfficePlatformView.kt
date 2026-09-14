package com.example.folio

import android.annotation.SuppressLint
import android.content.Context
import android.content.pm.ApplicationInfo
import android.graphics.Color
import android.net.Uri
import android.os.Build
import android.webkit.CookieManager
import android.webkit.JavascriptInterface
import android.webkit.RenderProcessGoneDetail
import android.webkit.WebChromeClient
import android.webkit.WebResourceRequest
import android.webkit.WebResourceResponse
import android.webkit.WebSettings
import android.webkit.WebView
import android.webkit.WebViewClient
import androidx.webkit.WebViewAssetLoader
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.StandardMessageCodec
import io.flutter.plugin.platform.PlatformView
import io.flutter.plugin.platform.PlatformViewFactory
import org.json.JSONObject
import java.io.ByteArrayInputStream

internal class OfficePlatformViewFactory(
    private val messenger: BinaryMessenger,
    private val documents: OfficeDocumentManager,
) : PlatformViewFactory(StandardMessageCodec.INSTANCE) {
    override fun create(context: Context, viewId: Int, args: Any?): PlatformView {
        val parameters = (args as? Map<*, *>) ?: emptyMap<Any, Any>()
        val sessionId = parameters["sessionId"] as? String
        val session = sessionId?.let(documents::session)
        return OfficePlatformView(context, viewId, messenger, session)
    }
}

@SuppressLint("SetJavaScriptEnabled")
internal class OfficePlatformView(
    context: Context,
    viewId: Int,
    messenger: BinaryMessenger,
    private val session: OfficeDocumentSession?,
) : PlatformView {
    private val viewContext = context
    private val channel = MethodChannel(messenger, "folio/office_view/$viewId")
    private var disposed = false
    private var started = false
    private val webView = WebView(context)
    private val assetLoader: WebViewAssetLoader

    init {
        assetLoader = WebViewAssetLoader.Builder()
            .setDomain(WebViewAssetLoader.DEFAULT_DOMAIN)
            .addPathHandler(
                "/assets/",
                WebViewAssetLoader.AssetsPathHandler(context.applicationContext),
            )
            .addPathHandler("/document/", ActiveDocumentPathHandler(session))
            .build()

        configureWebView()
        configureChannel()

    }

    override fun getView(): WebView = webView

    override fun dispose() {
        if (disposed) return
        disposed = true
        channel.setMethodCallHandler(null)
        webView.apply {
            stopLoading()
            loadUrl("about:blank")
            clearHistory()
            removeJavascriptInterface("FolioBridge")
            removeAllViews()
            destroy()
        }
    }

    private fun configureChannel() {
        channel.setMethodCallHandler { call, result ->
            if (disposed) {
                result.error("view_closed", "The Office view is closed.", null)
                return@setMethodCallHandler
            }
            when (call.method) {
                "start" -> {
                    start()
                    result.success(null)
                }
                "search" -> {
                    val query = call.argument<String>("query") ?: ""
                    evaluate("window.FolioOffice?.search(${JSONObject.quote(query)});")
                    result.success(null)
                }
                "nextHit" -> {
                    evaluate("window.FolioOffice?.nextHit();")
                    result.success(null)
                }
                "previousHit" -> {
                    evaluate("window.FolioOffice?.previousHit();")
                    result.success(null)
                }
                "goToPosition" -> {
                    val index = call.argument<Number>("index")?.toInt() ?: 0
                    evaluate("window.FolioOffice?.goToPosition($index);")
                    result.success(null)
                }
                "reload" -> {
                    webView.reload()
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun evaluate(script: String) {
        webView.evaluateJavascript(script, null)
    }

    private fun start() {
        if (started || disposed) return
        started = true
        val activeSession = session
        if (activeSession == null) {
            emit(
                mapOf(
                    "type" to "error",
                    "message" to "The Office document session has expired.",
                    "recoverable" to true,
                ),
            )
            return
        }
        val url = Uri.Builder()
            .scheme("https")
            .authority(WebViewAssetLoader.DEFAULT_DOMAIN)
            .appendPath("assets")
            .appendPath("office")
            .appendPath("${activeSession.format.wireName}.html")
            .appendQueryParameter("format", activeSession.format.wireName)
            .build()
        webView.loadUrl(url.toString())
    }

    private fun emit(event: Map<String, Any?>) {
        webView.post {
            if (!disposed) channel.invokeMethod("event", event)
        }
    }

    private fun emitJson(raw: String) {
        runCatching {
            val json = JSONObject(raw)
            val event = mutableMapOf<String, Any?>()
            json.keys().forEach { key ->
                val value = json.opt(key)
                event[key] = if (value == JSONObject.NULL) {
                    null
                } else if (value is Boolean || value is Number || value is String) {
                    value
                } else {
                    value?.toString()
                }
            }
            emit(event)
        }
    }

    private fun blockedResponse(): WebResourceResponse = WebResourceResponse(
        "text/plain",
        "utf-8",
        403,
        "Blocked",
        mapOf("Cache-Control" to "no-store"),
        ByteArrayInputStream(ByteArray(0)),
    )

    private fun configureWebView() {
        webView.setBackgroundColor(Color.TRANSPARENT)
        webView.setLayerType(WebView.LAYER_TYPE_HARDWARE, null)
        webView.setRendererPriorityPolicy(WebView.RENDERER_PRIORITY_BOUND, true)
        WebView.setWebContentsDebuggingEnabled(
            viewContext.applicationInfo.flags and ApplicationInfo.FLAG_DEBUGGABLE != 0,
        )
        CookieManager.getInstance().setAcceptThirdPartyCookies(webView, false)
        webView.settings.apply {
            javaScriptEnabled = true
            domStorageEnabled = false
            cacheMode = WebSettings.LOAD_NO_CACHE
            allowFileAccess = false
            allowContentAccess = false
            javaScriptCanOpenWindowsAutomatically = false
            setSupportMultipleWindows(false)
            mixedContentMode = WebSettings.MIXED_CONTENT_NEVER_ALLOW
            mediaPlaybackRequiresUserGesture = true
            builtInZoomControls = true
            displayZoomControls = false
            setSupportZoom(true)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                safeBrowsingEnabled = true
            }
        }
        webView.removeJavascriptInterface("searchBoxJavaBridge_")
        webView.removeJavascriptInterface("accessibility")
        webView.removeJavascriptInterface("accessibilityTraversal")
        webView.addJavascriptInterface(
            object {
                @JavascriptInterface
                fun postMessage(message: String) = emitJson(message)
            },
            "FolioBridge",
        )
        webView.setDownloadListener { _, _, _, _, _ ->
            emit(
                mapOf(
                    "type" to "blocked",
                    "message" to "Downloads are disabled in documents.",
                ),
            )
        }
        webView.webChromeClient = object : WebChromeClient() {
            override fun onCreateWindow(
                view: WebView?,
                isDialog: Boolean,
                isUserGesture: Boolean,
                resultMsg: android.os.Message?,
            ): Boolean = false
        }
        webView.webViewClient = object : WebViewClient() {
            override fun shouldOverrideUrlLoading(
                view: WebView?,
                request: WebResourceRequest?,
            ): Boolean = true

            override fun shouldInterceptRequest(
                view: WebView?,
                request: WebResourceRequest?,
            ): WebResourceResponse? {
                val uri = request?.url ?: return blockedResponse()
                if (uri.scheme != "https" || uri.host != WebViewAssetLoader.DEFAULT_DOMAIN) {
                    return blockedResponse()
                }
                return assetLoader.shouldInterceptRequest(uri) ?: blockedResponse()
            }

            override fun onRenderProcessGone(
                view: WebView?,
                detail: RenderProcessGoneDetail?,
            ): Boolean {
                channel.invokeMethod(
                    "event",
                    mapOf(
                        "type" to "error",
                        "message" to if (detail?.didCrash() == true) {
                            "The Office renderer stopped unexpectedly."
                        } else {
                            "Android reclaimed the Office renderer."
                        },
                        "recoverable" to true,
                    ),
                )
                if (!disposed) {
                    disposed = true
                    channel.setMethodCallHandler(null)
                    webView.removeJavascriptInterface("FolioBridge")
                    webView.removeAllViews()
                    webView.destroy()
                }
                return true
            }
        }
    }

    private class ActiveDocumentPathHandler(
        private val session: OfficeDocumentSession?,
    ) : WebViewAssetLoader.PathHandler {
        override fun handle(path: String): WebResourceResponse {
            if (path != "active" || session == null) {
                return WebResourceResponse(
                    "text/plain",
                    "utf-8",
                    404,
                    "Not found",
                    mapOf("Cache-Control" to "no-store"),
                    ByteArrayInputStream(ByteArray(0)),
                )
            }
            return try {
                WebResourceResponse(
                    session.format.mimeType,
                    null,
                    200,
                    "OK",
                    mapOf(
                        "Cache-Control" to "no-store",
                        "Content-Security-Policy" to "default-src 'none'",
                        "X-Content-Type-Options" to "nosniff",
                    ),
                    session.openStream().buffered(),
                )
            } catch (_: Exception) {
                WebResourceResponse(
                    "text/plain",
                    "utf-8",
                    404,
                    "Not found",
                    mapOf("Cache-Control" to "no-store"),
                    ByteArrayInputStream(ByteArray(0)),
                )
            }
        }
    }
}
