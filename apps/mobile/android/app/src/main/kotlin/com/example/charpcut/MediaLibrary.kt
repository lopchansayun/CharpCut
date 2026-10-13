package com.example.charpcut

import android.app.Activity
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Matrix
import android.media.MediaCodecList
import android.media.MediaExtractor
import android.media.MediaFormat
import android.media.MediaMetadataRetriever
import android.net.Uri
import android.os.Build
import android.provider.OpenableColumns
import android.util.AtomicFile
import androidx.exifinterface.media.ExifInterface
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import java.io.FileOutputStream
import java.security.MessageDigest
import java.util.UUID
import java.util.concurrent.Executors

/** Device media/catalog only. Timeline operations remain in the Rust engine. */
class MediaLibrary(private val activity: Activity, messenger: BinaryMessenger) {
    private val channel = MethodChannel(messenger, "charpcut/media")
    private val io = Executors.newSingleThreadExecutor()
    private val thumbnails = Executors.newSingleThreadExecutor()
    private val root = File(activity.filesDir, "media")
    private val cache = File(activity.cacheDir, "media-thumbnails")
    private val requestCode = 2120
    private var pending: MethodChannel.Result? = null
    private var pendingKind = "video"
    @Volatile private var disposed = false

    init {
        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "pickVideo", "importMedia" -> {
                    val kind = if (call.method == "pickVideo") "video" else call.argument<String>("kind")
                    if (kind !in listOf("video", "audio", "image")) {
                        result.error("invalid_kind", "Choose video, audio, or image", null)
                    } else if (pending != null) {
                        result.error("import_busy", "Finish the current import first", null)
                    } else {
                        pending = result
                        pendingKind = kind!!
                        try {
                            activity.startActivityForResult(Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
                                addCategory(Intent.CATEGORY_OPENABLE)
                                type = "$kind/*"
                                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                            }, requestCode)
                        } catch (error: Exception) {
                            pending = null
                            result.error("picker_failed", error.message, null)
                        }
                    }
                }
                "listMedia" -> work(result) { listMedia() }
                "inspectMedia" -> work(result) {
                    val file = sourceFile(call.argument<String>("path") ?: "")
                    val metadata = probe(file, null)
                    metadata.put("name", readCatalog(file.parentFile!!)?.optString("name") ?: file.name)
                    metadata.put("imported_at", readCatalog(file.parentFile!!)?.optLong("imported_at") ?: file.lastModified())
                    writeCatalog(file.parentFile!!, metadata)
                    map(metadata)
                }
                "checkPaths" -> work(result) {
                    (call.argument<List<String>>("paths") ?: emptyList()).distinct().mapNotNull { path ->
                        try { sourceFile(path); null } catch (error: Exception) {
                            mapOf("path" to path, "error" to (error.message ?: "Media is unavailable"))
                        }
                    }
                }
                "thumbnail" -> work(result, thumbnail = true) {
                    thumbnail(sourceFile(call.argument<String>("path") ?: ""),
                        call.argument<Number>("position_ms")?.toLong() ?: 0)
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun work(result: MethodChannel.Result, thumbnail: Boolean = false, body: () -> Any?) {
        (if (thumbnail) thumbnails else io).execute {
            try {
                val value = body()
                activity.runOnUiThread { if (!disposed) result.success(value) }
            } catch (error: Exception) {
                activity.runOnUiThread { if (!disposed) result.error("media_error", error.message ?: "Could not read media", null) }
            }
        }
    }

    fun onActivityResult(code: Int, resultCode: Int, data: Intent?) {
        if (code != requestCode) return
        val result = pending ?: return
        val kind = pendingKind
        val uri = data?.data
        if (resultCode != Activity.RESULT_OK || uri == null) {
            pending = null
            result.success(null)
            return
        }
        // Retain pending until copying finishes to prevent a second picker.
        io.execute {
            try {
                val imported = importMedia(uri, kind)
                activity.runOnUiThread {
                    if (!disposed) { pending = null; result.success(imported) }
                }
            } catch (error: Exception) {
                activity.runOnUiThread {
                    if (!disposed) { pending = null; result.error("media_import", error.message, null) }
                }
            }
        }
    }

    private fun importMedia(uri: Uri, kind: String): Map<String, Any?> {
        check(root.isDirectory || root.mkdirs()) { "Could not create media storage" }
        val folder = File(root, UUID.randomUUID().toString())
        check(folder.mkdir()) { "Could not create media storage" }
        val temporary = File(folder, "import.pending")
        var target: File? = null
        try {
            val displayName = activity.contentResolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)?.use {
                if (it.moveToFirst()) it.getString(0) else null
            } ?: "Imported $kind"
            val safeName = displayName.replace(Regex("[^A-Za-z0-9._-]"), "_").take(100)
            // A prefix avoids collisions with the catalog and temporary filenames.
            val destination = File(folder, "source-${safeName.ifBlank { kind }}")
            target = destination
            activity.contentResolver.openInputStream(uri)?.use { input ->
                FileOutputStream(temporary).use { output ->
                    input.copyTo(output)
                    output.fd.sync()
                }
            } ?: error("Could not read the selected file. Select an accessible local file and try again.")
            check(temporary.length() > 0) { "The selected file is empty" }
            val metadata = probe(temporary, kind)
            check(temporary.renameTo(destination)) { "Could not store imported media" }
            metadata.put("path", destination.absolutePath).put("id", folder.name)
                .put("name", displayName).put("imported_at", System.currentTimeMillis())
            writeCatalog(folder, metadata)
            return map(metadata)
        } catch (error: Exception) {
            // Only this newly created import's files are removed on failure.
            temporary.delete()
            target?.delete()
            AtomicFile(File(folder, "metadata.json")).delete()
            folder.delete()
            throw error
        }
    }

    private fun sourceFile(path: String): File {
        val file = File(path).canonicalFile
        check(file.parentFile?.parentFile == root.canonicalFile && file.name != "metadata.json" && !file.name.endsWith(".pending")) {
            "This media is outside the imported library. Import it again from Files."
        }
        check(file.isFile && file.canRead() && file.length() > 0) {
            "The imported file is missing or inaccessible. Import the original again."
        }
        return file
    }

    private fun number(format: MediaFormat, key: String): Number? {
        if (!format.containsKey(key)) return null
        return try { format.getInteger(key) } catch (_: Exception) {
            try { format.getFloat(key) } catch (_: Exception) { null }
        }
    }

    private fun probe(file: File, expected: String?): JSONObject {
        val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        BitmapFactory.decodeFile(file.absolutePath, bounds)
        val image = bounds.outWidth > 0 && bounds.outHeight > 0
        val item = JSONObject().put("version", 1).put("path", file.absolutePath)
            .put("id", file.parentFile!!.name).put("name", file.name)
            .put("size_bytes", file.length()).put("available", true)
        if (image) {
            check(expected == null || expected == "image") { "The selected file is an image, not $expected" }
            val exif = try { ExifInterface(file.absolutePath) } catch (_: Exception) { null }
            val rotation = exif?.rotationDegrees ?: 0
            item.put("kind", "image").put("width", bounds.outWidth).put("height", bounds.outHeight)
                .put("rotation", rotation).put("mirrored", exif?.isFlipped ?: false)
                .put("mime", bounds.outMimeType).put("duration_ms", 0).put("audio_streams", JSONArray())
            // Decode a bounded thumbnail to reject corrupt images before accepting them.
            val bitmap = imageBitmap(file)
            bitmap.recycle()
            return item
        }
        check(expected != "image") { "This image format cannot be decoded on this device" }
        val retriever = MediaMetadataRetriever()
        try {
            retriever.setDataSource(file.absolutePath)
            val video = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_HAS_VIDEO) == "yes"
            val audio = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_HAS_AUDIO) == "yes"
            val kind = if (video) "video" else "audio"
            check(video || audio) { "The file contains no supported video or audio" }
            check(expected == null || expected == kind) { "The selected file does not contain $expected media" }
            val duration = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_DURATION)?.toLongOrNull() ?: 0
            check(duration >= 100) { "The media is too short or has no readable duration" }
            item.put("kind", kind).put("duration_ms", duration).put("has_audio", audio)
                .put("mime", retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_MIMETYPE))
                .put("rotation", retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_ROTATION)?.toIntOrNull() ?: 0)
            if (video) {
                item.put("width", retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_WIDTH)?.toIntOrNull())
                    .put("height", retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_HEIGHT)?.toIntOrNull())
                val frame = videoBitmap(retriever, 0) ?: error("This video's frames cannot be decoded on this device")
                frame.recycle()
            }
            val streams = JSONArray()
            val extractor = MediaExtractor()
            try {
                extractor.setDataSource(file.absolutePath)
                for (i in 0 until extractor.trackCount) {
                    val format = extractor.getTrackFormat(i)
                    val mime = format.getString(MediaFormat.KEY_MIME) ?: continue
                    if (mime.startsWith("video/")) {
                        val fps = number(format, MediaFormat.KEY_FRAME_RATE)?.toDouble()
                        if (fps != null && fps.isFinite() && fps > 0) item.put("frame_rate", fps)
                    }
                    if (mime.startsWith("audio/")) {
                        val decodable = MediaCodecList(MediaCodecList.ALL_CODECS).findDecoderForFormat(format) != null
                        streams.put(JSONObject().put("codec", mime)
                            .put("channels", number(format, MediaFormat.KEY_CHANNEL_COUNT))
                            .put("sample_rate", number(format, MediaFormat.KEY_SAMPLE_RATE))
                            .put("bitrate", number(format, MediaFormat.KEY_BIT_RATE))
                            .put("decodable", decodable))
                    }
                }
            } finally { extractor.release() }
            if (kind == "audio") {
                check((0 until streams.length()).any { streams.getJSONObject(it).optBoolean("decodable") }) {
                    "This audio codec is not supported on this device"
                }
            }
            if (video && !item.has("frame_rate") && Build.VERSION.SDK_INT >= 28) {
                val frameCount = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_FRAME_COUNT)?.toLongOrNull()
                if (frameCount != null && frameCount > 0) {
                    item.put("frame_rate", frameCount.toDouble() * 1000 / duration).put("frame_rate_estimated", true)
                }
            }
            item.put("audio_streams", streams)
            return item
        } finally { retriever.release() }
    }

    @Synchronized
    private fun readCatalog(folder: File): JSONObject? {
        val file = AtomicFile(File(folder, "metadata.json"))
        return try { file.openRead().bufferedReader().use { JSONObject(it.readText()) } }
            catch (_: Exception) { null }
    }

    @Synchronized
    private fun writeCatalog(folder: File, item: JSONObject) {
        val file = AtomicFile(File(folder, "metadata.json"))
        val stream = file.startWrite()
        try { stream.write(item.toString().toByteArray(Charsets.UTF_8)); file.finishWrite(stream) }
        catch (error: Exception) { file.failWrite(stream); throw error }
    }

    private fun listMedia(): List<Map<String, Any?>> {
        if (!root.exists()) return emptyList()
        val folders = root.listFiles() ?: error("Could not read the media library")
        return folders.filter { it.isDirectory }.mapNotNull { folder ->
            val existing = readCatalog(folder)
            val file = existing?.optString("path")?.takeIf { it.isNotBlank() }?.let { File(it) }
                ?: folder.listFiles()?.firstOrNull { it.isFile && !it.name.startsWith("metadata.json") && !it.name.endsWith(".pending") }
                ?: return@mapNotNull null
            try {
                sourceFile(file.absolutePath)
                check(existing == null || existing.optInt("version") == 1) { "This media record needs a newer app version" }
                val item = existing ?: probe(file, null).put("imported_at", file.lastModified()).also { writeCatalog(folder, it) }
                map(item.put("available", true))
            } catch (error: Exception) {
                map((existing ?: JSONObject().put("id", folder.name).put("path", file.absolutePath)
                    .put("name", file.name).put("kind", "unknown").put("imported_at", file.lastModified()))
                    .put("available", false).put("error", error.message))
            }
        }.sortedByDescending { (it["imported_at"] as? Number)?.toLong() ?: 0 }
    }

    private fun imageBitmap(file: File): Bitmap {
        val options = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        BitmapFactory.decodeFile(file.absolutePath, options)
        options.inSampleSize = 1
        while (maxOf(options.outWidth, options.outHeight) / options.inSampleSize > 640) options.inSampleSize *= 2
        options.inJustDecodeBounds = false
        val source = BitmapFactory.decodeFile(file.absolutePath, options) ?: error("Image could not be decoded")
        val exif = try { ExifInterface(file.absolutePath) } catch (_: Exception) { null }
        val matrix = Matrix()
        // EXIF defines mirroring before rotation.
        if (exif?.isFlipped == true) matrix.postScale(-1f, 1f)
        matrix.postRotate((exif?.rotationDegrees ?: 0).toFloat())
        val oriented = Bitmap.createBitmap(source, 0, 0, source.width, source.height, matrix, true)
        if (oriented !== source) source.recycle()
        return oriented
    }

    private fun videoBitmap(retriever: MediaMetadataRetriever, timeMs: Long): Bitmap? {
        return if (Build.VERSION.SDK_INT >= 27) {
            retriever.getScaledFrameAtTime(timeMs * 1000, MediaMetadataRetriever.OPTION_CLOSEST_SYNC, 320, 320)
        } else {
            val source = retriever.getFrameAtTime(timeMs * 1000, MediaMetadataRetriever.OPTION_CLOSEST_SYNC) ?: return null
            val scale = 320.0 / maxOf(source.width, source.height)
            val small = Bitmap.createScaledBitmap(source, maxOf(1, (source.width * scale).toInt()), maxOf(1, (source.height * scale).toInt()), true)
            if (small !== source) source.recycle()
            small
        }
    }

    private fun thumbnail(file: File, requestedMs: Long): String? {
        val catalog = readCatalog(file.parentFile!!)
        val kind = catalog?.optString("kind") ?: "video"
        if (kind == "audio") return null
        val durationLimit = catalog?.optLong("duration_ms")?.takeIf { it > 0 } ?: (Long.MAX_VALUE / 1000)
        val timeMs = requestedMs.coerceIn(0, minOf(Long.MAX_VALUE / 1000, durationLimit - 1))
        val key = MessageDigest.getInstance("SHA-256").digest("${file.absolutePath}:${file.length()}:${file.lastModified()}:$timeMs".toByteArray())
            .joinToString("") { "%02x".format(it) }
        check(cache.isDirectory || cache.mkdirs()) { "Could not create thumbnail cache" }
        val output = File(cache, "$key.jpg")
        if (output.isFile && output.length() > 0) { output.setLastModified(System.currentTimeMillis()); return output.absolutePath }
        val bitmap = if (kind == "image") imageBitmap(file) else {
            val retriever = MediaMetadataRetriever()
            try { retriever.setDataSource(file.absolutePath); videoBitmap(retriever, timeMs) }
            finally { retriever.release() }
        } ?: error("No preview frame could be decoded")
        val atomic = AtomicFile(output)
        try {
            val stream = atomic.startWrite()
            try {
                check(bitmap.compress(Bitmap.CompressFormat.JPEG, 80, stream)) { "Could not save thumbnail" }
                atomic.finishWrite(stream)
            } catch (error: Exception) { atomic.failWrite(stream); throw error }
        } finally { bitmap.recycle() }
        // Bound derived cache files; never touch imported sources.
        val files = cache.listFiles()?.filter { it.extension == "jpg" }?.sortedBy { it.lastModified() } ?: emptyList()
        var bytes = files.sumOf { it.length() }
        for (old in files) {
            if (bytes <= 48L * 1024 * 1024) break
            if (old != output) { val size = old.length(); if (old.delete()) bytes -= size }
        }
        return output.absolutePath
    }

    private fun map(json: JSONObject): Map<String, Any?> = json.keys().asSequence().associateWith { key ->
        when (val value = json.get(key)) {
            JSONObject.NULL -> null
            is JSONObject -> map(value)
            is JSONArray -> (0 until value.length()).map { index ->
                val item = value.get(index)
                if (item is JSONObject) map(item) else if (item == JSONObject.NULL) null else item
            }
            else -> value
        }
    }

    fun dispose() {
        disposed = true
        pending?.error("import_cancelled", "The app closed during import. Check the library when reopening.", null)
        pending = null
        channel.setMethodCallHandler(null)
        io.shutdown()
        thumbnails.shutdown()
    }
}
