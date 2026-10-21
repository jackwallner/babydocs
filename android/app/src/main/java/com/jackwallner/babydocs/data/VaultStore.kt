package com.jackwallner.babydocs.data

import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.ImageDecoder
import android.net.Uri
import android.os.Build
import java.io.File
import java.util.UUID

/**
 * Photographs of documents the family already owns (`VaultStore.swift`).
 * Files live in app-private storage, excluded from every backup and device
 * transfer by the manifest, and `VaultDocument` rows hold filenames only.
 * There is deliberately no API here that returns a path or a `Uri`, so no
 * share sheet or exporter can reach an image even by accident. Deleting is
 * immediate: an image is never left orphaned on disk.
 */
class VaultStore(context: Context) {
    private val directory = File(context.filesDir, "vault").apply { mkdirs() }
    private val resolver = context.contentResolver

    /** Re-encodes the picked image as a JPEG in the vault and returns its filename. */
    fun importImage(uri: Uri): String? = runCatching {
        val bitmap = decode(uri) ?: return null
        val name = "${UUID.randomUUID()}.jpg"
        File(directory, name).outputStream().use { bitmap.compress(Bitmap.CompressFormat.JPEG, 88, it) }
        name
    }.getOrNull()

    fun loadImage(fileName: String, maxDimension: Int = 1600): Bitmap? {
        val file = File(directory, File(fileName).name)
        if (!file.isFile) return null
        val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        BitmapFactory.decodeFile(file.path, bounds)
        var sample = 1
        while (maxOf(bounds.outWidth, bounds.outHeight) / (sample * 2) >= maxDimension) sample *= 2
        return BitmapFactory.decodeFile(file.path, BitmapFactory.Options().apply { inSampleSize = sample })
    }

    fun delete(fileNames: List<String>) {
        fileNames.forEach { File(directory, File(it).name).delete() }
    }

    private fun decode(uri: Uri): Bitmap? = if (Build.VERSION.SDK_INT >= 28) {
        ImageDecoder.decodeBitmap(ImageDecoder.createSource(resolver, uri)) { decoder, info, _ ->
            decoder.allocator = ImageDecoder.ALLOCATOR_SOFTWARE
            val longest = maxOf(info.size.width, info.size.height)
            if (longest > MAX_STORED) {
                val scale = MAX_STORED.toFloat() / longest
                decoder.setTargetSize((info.size.width * scale).toInt(), (info.size.height * scale).toInt())
            }
        }
    } else {
        resolver.openInputStream(uri)?.use(BitmapFactory::decodeStream)
    }

    private companion object {
        const val MAX_STORED = 2400
    }
}
