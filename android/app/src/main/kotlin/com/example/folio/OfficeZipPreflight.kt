package com.example.folio

import java.io.InputStream
import java.util.zip.ZipInputStream

internal class OfficeArchiveException(
    val code: String,
    override val message: String,
) : Exception(message)

internal object OfficeZipPreflight {
    const val MAX_COMPRESSED_BYTES = 256L * 1024 * 1024
    const val MAX_EXPANDED_BYTES = 512L * 1024 * 1024
    const val MAX_ENTRY_BYTES = 128L * 1024 * 1024
    const val MAX_ENTRIES = 4096
    const val MAX_RATIO = 200L
    private const val MAX_NAME_LENGTH = 512

    fun validate(
        format: OfficeFormat,
        compressedSize: Long,
        openStream: () -> InputStream,
    ) {
        if (compressedSize > MAX_COMPRESSED_BYTES) {
            throw OfficeArchiveException(
                "archive_too_large",
                "This Office file is too large to open safely.",
            )
        }
        var entries = 0
        var expandedTotal = 0L
        var hasContentTypes = false
        var hasMainPart = false
        val names = HashSet<String>()
        val buffer = ByteArray(DEFAULT_BUFFER_SIZE)

        openStream().buffered().use { source ->
            ZipInputStream(source).use { zip ->
                while (true) {
                    val entry = zip.nextEntry ?: break
                    entries += 1
                    if (entries > MAX_ENTRIES) {
                        throw OfficeArchiveException(
                            "unsafe_archive",
                            "This Office file contains too many archive entries.",
                        )
                    }
                    val name = normalizedEntryName(entry.name)
                    if (!names.add(name)) {
                        throw OfficeArchiveException(
                            "unsafe_archive",
                            "This Office file contains duplicate archive paths.",
                        )
                    }
                    hasContentTypes = hasContentTypes || name == "[Content_Types].xml"
                    hasMainPart = hasMainPart || when (format) {
                        OfficeFormat.DOCX -> name == "word/document.xml"
                        OfficeFormat.PPTX -> name == "ppt/presentation.xml"
                    }
                    if (entry.isDirectory) {
                        zip.closeEntry()
                        continue
                    }
                    var entryExpanded = 0L
                    while (true) {
                        val count = zip.read(buffer)
                        if (count < 0) break
                        entryExpanded += count
                        expandedTotal += count
                        if (entryExpanded > MAX_ENTRY_BYTES || expandedTotal > MAX_EXPANDED_BYTES) {
                            throw OfficeArchiveException(
                                "archive_too_large",
                                "This Office file expands beyond the safe rendering limit.",
                            )
                        }
                    }
                    val compressedEntrySize = entry.compressedSize
                    if (compressedEntrySize > 0 && entryExpanded / compressedEntrySize > MAX_RATIO) {
                        throw OfficeArchiveException(
                            "unsafe_archive",
                            "This Office file has an unsafe compression ratio.",
                        )
                    }
                    zip.closeEntry()
                }
            }
        }

        if (entries == 0 || !hasContentTypes || !hasMainPart) {
            throw OfficeArchiveException(
                "invalid_archive",
                "This file is not a valid ${format.wireName.uppercase()} document.",
            )
        }
        if (compressedSize > 0 && expandedTotal / compressedSize > MAX_RATIO) {
            throw OfficeArchiveException(
                "unsafe_archive",
                "This Office file has an unsafe compression ratio.",
            )
        }
    }

    private fun normalizedEntryName(rawName: String): String {
        val name = rawName.replace('\\', '/')
        val segments = name.split('/')
        if (name.isBlank() ||
            name.length > MAX_NAME_LENGTH ||
            name.startsWith('/') ||
            name.contains('\u0000') ||
            segments.any { it == ".." } ||
            segments.firstOrNull()?.contains(':') == true
        ) {
            throw OfficeArchiveException(
                "unsafe_archive",
                "This Office file contains an unsafe archive path.",
            )
        }
        return name
    }
}
