package com.example.folio

import android.app.Activity
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.os.storage.StorageManager
import android.provider.DocumentsContract
import android.provider.OpenableColumns
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileNotFoundException

class MainActivity : FlutterActivity() {
    private companion object {
        const val STORAGE_CHANNEL = "folio/storage"
        const val INTENTS_CHANNEL = "folio/intents"
        const val DOCUMENT_ACCESS_REQUEST = 6107
    }

    private var eventSink: EventChannel.EventSink? = null
    private var queuedIncoming: Map<String, Any?>? = null
    private var initialIntentConsumed = false
    private var documentAccessResult: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, STORAGE_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "getAccessState" -> result.success(Environment.isExternalStorageManager())
                    "openAllFilesSettings" -> {
                        openAllFilesSettings()
                        result.success(null)
                    }
                    "getStorageRoots" -> result.success(storageRoots())
                    "readContentUri" -> {
                        val rawUri = call.argument<String>("uri")
                        if (rawUri.isNullOrBlank()) {
                            result.error("invalid_uri", "The content URI is missing.", null)
                        } else {
                            readContentUri(rawUri, result)
                        }
                    }
                    "consumeInitialDocument" -> {
                        if (initialIntentConsumed) {
                            result.success(null)
                        } else {
                            initialIntentConsumed = true
                            result.success(documentFromIntent(intent))
                        }
                    }
                    "requestDocumentAccess" -> {
                        if (documentAccessResult != null) {
                            result.error(
                                "picker_active",
                                "A document access request is already active.",
                                null,
                            )
                        } else {
                            documentAccessResult = result
                            val mimeType = call.argument<String>("mimeType") ?: "*/*"
                            val picker = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
                                addCategory(Intent.CATEGORY_OPENABLE)
                                type = mimeType
                                addFlags(
                                    Intent.FLAG_GRANT_READ_URI_PERMISSION or
                                        Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION,
                                )
                            }
                            startActivityForResult(picker, DOCUMENT_ACCESS_REQUEST)
                        }
                    }
                    else -> result.notImplemented()
                }
            }

        EventChannel(flutterEngine.dartExecutor.binaryMessenger, INTENTS_CHANNEL)
            .setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
                    eventSink = events
                    queuedIncoming?.let {
                        events.success(it)
                        queuedIncoming = null
                    }
                }

                override fun onCancel(arguments: Any?) {
                    eventSink = null
                }
            })
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        val incoming = documentFromIntent(intent) ?: return
        eventSink?.success(incoming) ?: run { queuedIncoming = incoming }
    }

    @Deprecated("Deprecated in Android, retained for FlutterActivity result forwarding")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != DOCUMENT_ACCESS_REQUEST) return

        val pendingResult = documentAccessResult
        documentAccessResult = null
        if (pendingResult == null) return
        if (resultCode != Activity.RESULT_OK || data?.data == null) {
            pendingResult.success(null)
            return
        }
        pendingResult.success(documentFromUri(data.data!!, data.flags))
    }

    private fun openAllFilesSettings() {
        val packageUri = Uri.parse("package:$packageName")
        val appSettings = Intent(Settings.ACTION_MANAGE_APP_ALL_FILES_ACCESS_PERMISSION, packageUri)
        try {
            startActivity(appSettings)
        } catch (_: Exception) {
            startActivity(Intent(Settings.ACTION_MANAGE_ALL_FILES_ACCESS_PERMISSION))
        }
    }

    private fun storageRoots(): List<Map<String, Any>> {
        val manager = getSystemService(Context.STORAGE_SERVICE) as StorageManager
        return manager.storageVolumes
            .mapNotNull { volume ->
                runCatching {
                    volume.directory?.canonicalPath?.let { path ->
                        mapOf("path" to path, "isRemovable" to volume.isRemovable)
                    }
                }.getOrNull()
            }
            .distinctBy { it["path"] }
    }

    private fun documentFromIntent(sourceIntent: Intent?): Map<String, Any?>? {
        if (sourceIntent == null) return null
        val uri = when (sourceIntent.action) {
            Intent.ACTION_VIEW -> sourceIntent.data
            Intent.ACTION_SEND -> {
                sourceIntent.clipData?.takeIf { it.itemCount > 0 }?.getItemAt(0)?.uri
                    ?: streamUri(sourceIntent)
            }
            else -> null
        } ?: return null
        return documentFromUri(uri, sourceIntent.flags)
    }

    private fun readContentUri(rawUri: String, result: MethodChannel.Result) {
        Thread({
            try {
                val uri = Uri.parse(rawUri)
                val bytes = contentResolver.openInputStream(uri)?.use { stream ->
                    stream.readBytes()
                } ?: throw FileNotFoundException("The provider returned no stream.")
                runOnUiThread { result.success(bytes) }
            } catch (_: SecurityException) {
                runOnUiThread {
                    result.error(
                        "access_denied",
                        "Folio no longer has permission to read this file.",
                        null,
                    )
                }
            } catch (_: FileNotFoundException) {
                runOnUiThread {
                    result.error("not_found", "The file is no longer available.", null)
                }
            } catch (_: Exception) {
                runOnUiThread {
                    result.error("read_failed", "The file could not be read.", null)
                }
            }
        }, "folio-document-reader").start()
    }

    @Suppress("DEPRECATION")
    private fun streamUri(sourceIntent: Intent): Uri? {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            sourceIntent.getParcelableExtra(Intent.EXTRA_STREAM, Uri::class.java)
        } else {
            sourceIntent.getParcelableExtra(Intent.EXTRA_STREAM)
        }
    }

    private fun documentFromUri(uri: Uri, flags: Int): Map<String, Any?>? {
        var persisted = false
        if (uri.scheme == "content" &&
            flags and Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION != 0 &&
            flags and Intent.FLAG_GRANT_READ_URI_PERMISSION != 0
        ) {
            try {
                contentResolver.takePersistableUriPermission(
                    uri,
                    Intent.FLAG_GRANT_READ_URI_PERMISSION,
                )
                persisted = true
            } catch (_: SecurityException) {
                // Some providers advertise a persistable grant but reject taking it.
            }
        }

        if (uri.scheme == "file") {
            val path = uri.path ?: return null
            val file = File(path)
            return mapOf(
                "sourceType" to "file",
                "value" to file.absolutePath,
                "displayName" to file.name,
                "sizeBytes" to file.length(),
                "modifiedAtMillis" to file.lastModified(),
                "mimeType" to contentResolver.getType(uri),
                "persistedPermission" to false,
            )
        }

        var displayName = uri.lastPathSegment?.substringAfterLast('/') ?: "Untitled"
        var sizeBytes = 0L
        var modifiedAt = System.currentTimeMillis()
        try {
            contentResolver.query(uri, null, null, null, null)?.use { cursor ->
                if (cursor.moveToFirst()) {
                    cursor.getColumnIndex(OpenableColumns.DISPLAY_NAME)
                        .takeIf { it >= 0 }
                        ?.let { displayName = cursor.getString(it) ?: displayName }
                    cursor.getColumnIndex(OpenableColumns.SIZE)
                        .takeIf { it >= 0 && !cursor.isNull(it) }
                        ?.let { sizeBytes = cursor.getLong(it) }
                    cursor.getColumnIndex(DocumentsContract.Document.COLUMN_LAST_MODIFIED)
                        .takeIf { it >= 0 && !cursor.isNull(it) }
                        ?.let { modifiedAt = cursor.getLong(it) }
                }
            }
        } catch (_: Exception) {
            // Metadata is optional; the URI itself remains usable for this session.
        }
        return mapOf(
            "sourceType" to "uri",
            "value" to uri.toString(),
            "displayName" to displayName,
            "sizeBytes" to sizeBytes,
            "modifiedAtMillis" to modifiedAt,
            "mimeType" to contentResolver.getType(uri),
            "persistedPermission" to persisted,
        )
    }
}
