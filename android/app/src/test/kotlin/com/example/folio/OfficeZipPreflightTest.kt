package com.example.folio

import org.junit.Assert.assertEquals
import org.junit.Test
import java.io.ByteArrayInputStream
import java.io.ByteArrayOutputStream
import java.util.zip.ZipEntry
import java.util.zip.ZipOutputStream

class OfficeZipPreflightTest {
    @Test
    fun acceptsMinimalDocxPackage() {
        val archive = archive(
            "[Content_Types].xml" to "<Types/>",
            "_rels/.rels" to "<Relationships/>",
            "word/document.xml" to "<document/>",
        )

        OfficeZipPreflight.validate(OfficeFormat.DOCX, archive.size.toLong()) {
            ByteArrayInputStream(archive)
        }
    }

    @Test
    fun acceptsMinimalPptxPackage() {
        val archive = archive(
            "[Content_Types].xml" to "<Types/>",
            "ppt/presentation.xml" to "<presentation/>",
        )

        OfficeZipPreflight.validate(OfficeFormat.PPTX, archive.size.toLong()) {
            ByteArrayInputStream(archive)
        }
    }

    @Test
    fun rejectsArchiveTraversal() {
        val archive = archive(
            "[Content_Types].xml" to "<Types/>",
            "../word/document.xml" to "<document/>",
        )

        val error = runCatching {
            OfficeZipPreflight.validate(OfficeFormat.DOCX, archive.size.toLong()) {
                ByteArrayInputStream(archive)
            }
        }.exceptionOrNull() as OfficeArchiveException

        assertEquals("unsafe_archive", error.code)
    }

    @Test
    fun rejectsMissingMainPart() {
        val archive = archive("[Content_Types].xml" to "<Types/>")

        val error = runCatching {
            OfficeZipPreflight.validate(OfficeFormat.PPTX, archive.size.toLong()) {
                ByteArrayInputStream(archive)
            }
        }.exceptionOrNull() as OfficeArchiveException

        assertEquals("invalid_archive", error.code)
    }

    @Test
    fun rejectsExtremeCompressionRatio() {
        val archive = archive(
            "[Content_Types].xml" to "<Types/>",
            "word/document.xml" to "0".repeat(1024 * 1024),
        )

        val error = runCatching {
            OfficeZipPreflight.validate(OfficeFormat.DOCX, archive.size.toLong()) {
                ByteArrayInputStream(archive)
            }
        }.exceptionOrNull() as OfficeArchiveException

        assertEquals("unsafe_archive", error.code)
    }

    private fun archive(vararg entries: Pair<String, String>): ByteArray {
        val output = ByteArrayOutputStream()
        ZipOutputStream(output).use { zip ->
            entries.forEach { (name, content) ->
                zip.putNextEntry(ZipEntry(name))
                zip.write(content.toByteArray())
                zip.closeEntry()
            }
        }
        return output.toByteArray()
    }
}
