package com.example.folio

import android.content.Context
import android.net.Uri
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileInputStream
import java.io.FileNotFoundException
import java.io.InputStream
import java.util.UUID
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.ExecutorService
import java.util.zip.ZipException

internal enum class OfficeFormat(val wireName: String, val mimeType: String) {
    DOCX(
        "docx",
        "application/vnd.openxmlformats-officedocument.wordprocessingml.document",
    ),
    PPTX(
        "pptx",
        "application/vnd.openxmlformats-officedocument.presentationml.presentation",
    );

    companion object {
        fun fromWireName(value: String?): OfficeFormat? = entries.firstOrNull {
            it.wireName == value
        }
    }
}

internal data class OfficeDocumentSession(
    val id: String,
    val format: OfficeFormat,
    val sizeBytes: Long,
    private val streamFactory: () -> InputStream,
) {
    fun openStream(): InputStream = streamFactory()
}

internal class OfficeDocumentManager(
    context: Context,
    private val executor: ExecutorService,
) {
    private val appContext = context.applicationContext
    private val sessions = ConcurrentHashMap<String, OfficeDocumentSession>()

    fun handle(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "prepareDocument" -> prepare(call, result)
            "closeDocument" -> {
                call.argument<String>("sessionId")?.let(sessions::remove)
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    fun session(id: String): OfficeDocumentSession? = sessions[id]

    fun closeAll() = sessions.clear()

    private fun prepare(call: MethodCall, result: MethodChannel.Result) {
        val format = OfficeFormat.fromWireName(call.argument("format"))
        val sourceType = call.argument<String>("sourceType")
        val source = call.argument<String>("source")
        val declaredSize = call.argument<Number>("sizeBytes")?.toLong() ?: -1L
        if (format == null || source.isNullOrBlank() || sourceType !in setOf("file", "uri")) {
            result.error("invalid_source", "The Office document source is incomplete.", null)
            return
        }

        executor.execute {
            try {
                val streamFactory: () -> InputStream = when (sourceType) {
                    "file" -> {
                        val file = File(source)
                        if (!file.isFile) throw FileNotFoundException()
                        ({ FileInputStream(file) })
                    }
                    else -> {
                        val uri = Uri.parse(source)
                        ({
                            appContext.contentResolver.openInputStream(uri)
                                ?: throw FileNotFoundException()
                        })
                    }
                }
                val actualSize = when (sourceType) {
                    "file" -> File(source).length()
                    else -> declaredSize
                }
                OfficeZipPreflight.validate(
                    format = format,
                    compressedSize = actualSize,
                    openStream = streamFactory,
                )
                val id = UUID.randomUUID().toString()
                sessions[id] = OfficeDocumentSession(
                    id = id,
                    format = format,
                    sizeBytes = actualSize,
                    streamFactory = streamFactory,
                )
                appContext.mainExecutor.execute {
                    result.success(
                        mapOf(
                            "sessionId" to id,
                            "format" to format.wireName,
                            "sizeBytes" to actualSize,
                        ),
                    )
                }
            } catch (_: SecurityException) {
                appContext.mainExecutor.execute {
                    result.error(
                        "access_denied",
                        "Folio no longer has permission to read this file.",
                        null,
                    )
                }
            } catch (_: FileNotFoundException) {
                appContext.mainExecutor.execute {
                    result.error("not_found", "The file is no longer available.", null)
                }
            } catch (error: OfficeArchiveException) {
                appContext.mainExecutor.execute {
                    result.error(error.code, error.message, null)
                }
            } catch (_: ZipException) {
                appContext.mainExecutor.execute {
                    result.error("invalid_archive", "The Office archive is damaged.", null)
                }
            } catch (_: Exception) {
                appContext.mainExecutor.execute {
                    result.error("prepare_failed", "The Office document could not be prepared.", null)
                }
            }
        }
    }
}
