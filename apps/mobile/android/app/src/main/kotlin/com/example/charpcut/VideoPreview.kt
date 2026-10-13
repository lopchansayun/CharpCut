package com.example.charpcut

import android.content.Context
import android.net.Uri
import android.os.Handler
import android.os.Looper
import android.view.LayoutInflater
import android.view.View
import androidx.media3.common.MediaItem
import androidx.media3.common.PlaybackException
import androidx.media3.common.Player
import androidx.media3.common.util.UnstableApi
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.ui.PlayerView
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.StandardMessageCodec
import io.flutter.plugin.platform.PlatformView
import io.flutter.plugin.platform.PlatformViewFactory
import java.io.File

@UnstableApi
class VideoPreviewFactory(private val messenger: BinaryMessenger) : PlatformViewFactory(StandardMessageCodec.INSTANCE) {
    private val views = mutableSetOf<VideoPreview>()
    override fun create(context: Context, viewId: Int, args: Any?): PlatformView {
        val view = VideoPreview(context, viewId, messenger) { views.remove(it) }
        views.add(view)
        return view
    }
    fun pauseAll() = views.toList().forEach { it.pause() }
    fun disposeAll() = views.toList().forEach { it.dispose() }
}

private data class PreviewClip(val id: String, val path: String, val start: Long, val sourceIn: Long, val duration: Long)

/** Renders the clip ranges supplied by the Rust snapshot. It never edits them. */
@UnstableApi
class VideoPreview(context: Context, id: Int, messenger: BinaryMessenger, private val onDispose: (VideoPreview) -> Unit) : PlatformView {
    private val view = LayoutInflater.from(context).inflate(R.layout.charpcut_preview, null) as PlayerView
    private val player = ExoPlayer.Builder(context).build()
    private val channel = MethodChannel(messenger, "charpcut/preview/$id")
    private val handler = Handler(Looper.getMainLooper())
    private var clips = emptyList<PreviewClip>()
    private var revision = 0
    private var disposed = false
    private var updating = false
    private var hasFrame = false
    private var errorMessage: String? = null
    private val ticker = object : Runnable {
        override fun run() {
            if (disposed) return
            publish()
            handler.postDelayed(this, 100)
        }
    }

    init {
        view.player = player
        player.addListener(object : Player.Listener {
            override fun onEvents(player: Player, events: Player.Events) { publish() }
            override fun onRenderedFirstFrame() { hasFrame = true; publish() }
            override fun onPlayerError(error: PlaybackException) {
                errorMessage = "Could not play this video (${error.errorCodeName}): ${error.message ?: "Unsupported or inaccessible source"}"
                player.pause()
                publish()
            }
        })
        channel.setMethodCallHandler { call, result ->
            if (disposed) {
                result.error("preview_closed", "The video preview has closed", null)
            } else if (call.method != "update") {
                result.notImplemented()
            } else {
                try {
                    update(call.arguments as? Map<*, *> ?: error("Missing preview settings"))
                    result.success(null)
                } catch (error: Exception) {
                    player.pause()
                    errorMessage = error.message ?: "Could not load the video preview"
                    publish()
                    result.error("preview_failed", errorMessage, null)
                }
            }
        }
        handler.post(ticker)
    }

    private fun update(args: Map<*, *>) {
        revision = (args["revision"] as Number).toInt()
        val next = (args["clips"] as List<*>).map { value ->
            val clip = value as Map<*, *>
            PreviewClip(clip["id"] as String, clip["path"] as String,
                (clip["start_ms"] as Number).toLong(), (clip["source_in_ms"] as Number).toLong(),
                (clip["duration_ms"] as Number).toLong())
        }
        var expectedStart = 0L
        for (clip in next) {
            require(clip.start == expectedStart && clip.sourceIn >= 0 && clip.duration > 0) { "Invalid video range in the project" }
            require(clip.path.isNotBlank() && !clip.path.startsWith("placeholder://")) { "This older sample clip has no video file. Delete it and import a real video with +." }
            if (!clip.path.contains("://")) require(File(clip.path).canRead()) { "The video file is missing or cannot be read. Import it again." }
            expectedStart = Math.addExact(expectedStart, clip.duration)
        }
        updating = true
        try {
            val changed = next != clips || errorMessage != null
            if (changed) {
                val items = next.map { clip ->
                    val uri = if (clip.path.contains("://")) Uri.parse(clip.path) else Uri.fromFile(File(clip.path))
                    MediaItem.Builder().setMediaId(clip.id).setUri(uri)
                        .setClippingConfiguration(MediaItem.ClippingConfiguration.Builder()
                            .setStartPositionMs(clip.sourceIn)
                            .setEndPositionMs(Math.addExact(clip.sourceIn, clip.duration)).build())
                        .build()
                }
                player.pause()
                clips = next
                hasFrame = false
                errorMessage = null
                player.setMediaItems(items)
                if (items.isNotEmpty()) player.prepare()
            }
            player.volume = if (args["muted"] == true) 0f else 1f
            if (clips.isNotEmpty() && (changed || args["seek"] == true)) {
                val position = (args["position_ms"] as Number).toLong().coerceIn(0L, expectedStart)
                val index = clips.indexOfLast { position >= it.start }.coerceAtLeast(0)
                val clip = clips[index]
                // Avoid seeking past the final frame when the playhead is at the end.
                val local = (position - clip.start).coerceIn(0L, (clip.duration - 1).coerceAtLeast(0))
                player.seekTo(index, local)
            }
            if (args["playing"] == true && clips.isNotEmpty() && errorMessage == null) player.play() else player.pause()
            view.keepScreenOn = player.playWhenReady
        } finally {
            updating = false
        }
        publish()
    }

    private fun publish() {
        if (disposed || updating) return
        val clip = clips.getOrNull(player.currentMediaItemIndex)
        val position = if (player.playbackState == Player.STATE_ENDED) clips.lastOrNull()?.let { it.start + it.duration } ?: 0L
            else clip?.let { it.start + player.currentPosition.coerceIn(0L, it.duration) } ?: 0L
        channel.invokeMethod("state", mapOf(
            "revision" to revision, "position_ms" to position,
            "playing" to (player.playWhenReady && player.playbackState != Player.STATE_ENDED && errorMessage == null),
            "has_frame" to hasFrame, "error" to errorMessage))
    }

    fun pause() {
        if (disposed) return
        player.pause()
        view.keepScreenOn = false
        publish()
    }
    override fun getView(): View = view
    override fun dispose() {
        if (disposed) return
        disposed = true
        handler.removeCallbacksAndMessages(null)
        channel.setMethodCallHandler(null)
        view.player = null
        player.release()
        onDispose(this)
    }
}
