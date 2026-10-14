package com.example.charpcut

import android.content.Context
import android.net.Uri
import android.os.Handler
import android.os.SystemClock
import android.os.Looper
import android.view.LayoutInflater
import android.view.View
import androidx.media3.common.AudioAttributes
import androidx.media3.common.C
import androidx.media3.common.VideoSize
import androidx.media3.exoplayer.SeekParameters
import androidx.media3.exoplayer.source.DefaultMediaSourceFactory
import androidx.media3.exoplayer.source.SilenceMediaSource
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

private data class PreviewClip(val id: String, val path: String, val start: Long, val sourceIn: Long, val duration: Long) {
    val isGap: Boolean get() = path.isEmpty()
}

/** Renders the clip ranges supplied by the Rust snapshot. It never edits them. */
@UnstableApi
class VideoPreview(private val context: Context, id: Int, messenger: BinaryMessenger, private val onDispose: (VideoPreview) -> Unit) : PlatformView {
    private val view = LayoutInflater.from(context).inflate(R.layout.charpcut_preview, null) as PlayerView
    private val player = ExoPlayer.Builder(context).build()
    private data class AudioLane(val player: ExoPlayer, val clips: List<PreviewClip>, var lastCorrection: Long = 0L)
    private val audioLanes = mutableListOf<AudioLane>()
    private val mediaSources = DefaultMediaSourceFactory(context)
    private var aspectRatio = 0.0
    private val channel = MethodChannel(messenger, "charpcut/preview/$id")
    private val handler = Handler(Looper.getMainLooper())
    private var clips = emptyList<PreviewClip>()
    private var audioClips = emptyList<PreviewClip>()
    private var clipVolumes = emptyMap<String, Float>()
    private var audioVolumes = emptyMap<String, Float>()
    private var requestedPlaying = false
    private var synchronizing = false
    private var lastPublished: Map<String, Any?>? = null
    private var muted = false
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
        player.setSeekParameters(SeekParameters.EXACT)
        player.setAudioAttributes(AudioAttributes.Builder()
            .setUsage(C.USAGE_MEDIA).setContentType(C.AUDIO_CONTENT_TYPE_MOVIE).build(), true)
        player.setHandleAudioBecomingNoisy(true)
        player.addListener(object : Player.Listener {
            override fun onEvents(player: Player, events: Player.Events) { publish() }
            override fun onPlaybackSuppressionReasonChanged(reason: Int) {
                if (reason != Player.PLAYBACK_SUPPRESSION_REASON_NONE) pause()
                publish()
            }
            override fun onRenderedFirstFrame() { hasFrame = true; publish() }
            override fun onVideoSizeChanged(size: VideoSize) {
                if (size.width > 0 && size.height > 0) {
                    aspectRatio = size.width.toDouble() * size.pixelWidthHeightRatio / size.height
                    publish()
                }
            }
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
                    audioLanes.forEach { it.player.pause() }
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
        val sourceClips = (args["clips"] as List<*>).map { value ->
            val clip = value as Map<*, *>
            PreviewClip(clip["id"] as String, clip["path"] as String,
                (clip["start_ms"] as Number).toLong(), (clip["source_in_ms"] as Number).toLong(),
                (clip["duration_ms"] as Number).toLong())
        }
        var expectedStart = 0L
        val next = mutableListOf<PreviewClip>()
        for (clip in sourceClips) {
            require(clip.start >= expectedStart && clip.sourceIn >= 0 && clip.duration > 0) { "Invalid or overlapping video range in the project" }
            require(clip.path.isNotBlank() && !clip.path.startsWith("placeholder://")) { "This older sample clip has no video file. Delete it and import a real video with +." }
            if (!clip.path.contains("://")) require(File(clip.path).isFile && File(clip.path).canRead()) { "${File(clip.path).name} is missing or cannot be read. Import it again." }
            require(Math.addExact(clip.sourceIn, clip.duration) <= Long.MAX_VALUE / 1000) { "Source duration is too large" }
            if (clip.start > expectedStart) next.add(PreviewClip("gap-$expectedStart", "", expectedStart, 0, clip.start - expectedStart))
            next.add(clip)
            expectedStart = Math.addExact(clip.start, clip.duration)
        }
        val total = (args["duration_ms"] as? Number)?.toLong() ?: expectedStart
        require(total >= expectedStart && total <= Long.MAX_VALUE / 1000) { "Invalid preview duration" }
        if (total > expectedStart) next.add(PreviewClip("gap-$expectedStart", "", expectedStart, 0, total - expectedStart))
        expectedStart = total
        val sourceAudio = (args["audio_clips"] as? List<*>) ?: emptyList<Any>()
        val nextAudio = sourceAudio.map { value ->
            val item = value as Map<*, *>
            val clip = PreviewClip(item["id"] as String, item["path"] as String,
                (item["start_ms"] as Number).toLong(), (item["source_in_ms"] as Number).toLong(),
                (item["duration_ms"] as Number).toLong())
            require(clip.start >= 0 && clip.sourceIn >= 0 && clip.duration > 0 && Math.addExact(clip.start, clip.duration) <= total) { "Invalid audio range in the project" }
            require(clip.path.isNotBlank()) { "Audio source is missing" }
            if (!clip.path.contains("://")) require(File(clip.path).isFile && File(clip.path).canRead()) { "${File(clip.path).name} is missing or cannot be read" }
            require(Math.addExact(clip.sourceIn, clip.duration) <= Long.MAX_VALUE / 1000) { "Audio duration is too large" }
            clip
        }.sortedBy { it.start }
        updating = true
        try {
            val changed = next != clips || args["retry"] == true
            val audioChanged = nextAudio != audioClips || next.lastOrNull()?.let { it.start + it.duration } != clips.lastOrNull()?.let { it.start + it.duration } || args["retry"] == true
            if (changed) {
                val sources = next.map { clip ->
                    if (clip.isGap) {
                        SilenceMediaSource.Factory().setDurationUs(clip.duration * 1000).createMediaSource()
                    } else {
                        val uri = if (clip.path.contains("://")) Uri.parse(clip.path) else Uri.fromFile(File(clip.path))
                        mediaSources.createMediaSource(MediaItem.Builder().setMediaId(clip.id).setUri(uri)
                            .setClippingConfiguration(MediaItem.ClippingConfiguration.Builder()
                                .setStartPositionMs(clip.sourceIn)
                                .setEndPositionMs(Math.addExact(clip.sourceIn, clip.duration)).build())
                            .build())
                    }
                }
                player.pause()
                clips = next
                hasFrame = false
                errorMessage = null
                player.setMediaSources(sources)
                if (sources.isNotEmpty()) player.prepare()
            }
            if (audioChanged) {
                // Reuse sequential clips in one decoder; allocate more only for overlap.
                audioLanes.forEach { it.player.release() }
                audioLanes.clear()
                audioClips = nextAudio
                errorMessage = null
                val packed = mutableListOf<MutableList<PreviewClip>>()
                for (clip in nextAudio) {
                    val lane = packed.firstOrNull { it.last().let { c -> c.start + c.duration <= clip.start } }
                        ?: mutableListOf<PreviewClip>().also { packed.add(it) }
                    lane.add(clip)
                }
                for (range in packed) {
                    val filled = mutableListOf<PreviewClip>()
                    var end = 0L
                    for (clip in range) {
                        if (clip.start > end) filled.add(PreviewClip("gap-$end", "", end, 0, clip.start - end))
                        filled.add(clip)
                        end = clip.start + clip.duration
                    }
                    if (total > end) filled.add(PreviewClip("gap-$end", "", end, 0, total - end))
                    val decoder = ExoPlayer.Builder(context).build()
                    val lane = AudioLane(decoder, filled)
                    audioLanes.add(lane)
                    decoder.setSeekParameters(SeekParameters.EXACT)
                    decoder.setAudioAttributes(AudioAttributes.Builder().setUsage(C.USAGE_MEDIA)
                        .setContentType(C.AUDIO_CONTENT_TYPE_MUSIC).build(), false)
                    decoder.addListener(object : Player.Listener {
                        override fun onEvents(player: Player, events: Player.Events) { publish() }
                        override fun onPlayerError(error: PlaybackException) {
                            errorMessage = "Could not play timeline audio (${error.errorCodeName}): ${error.message}"
                            pause()
                        }
                    })
                    decoder.setMediaSources(filled.map { clip ->
                        if (clip.isGap) SilenceMediaSource.Factory().setDurationUs(clip.duration * 1000).createMediaSource()
                        else {
                            val uri = if (clip.path.contains("://")) Uri.parse(clip.path) else Uri.fromFile(File(clip.path))
                            mediaSources.createMediaSource(MediaItem.Builder().setMediaId(clip.id).setUri(uri)
                                .setClippingConfiguration(MediaItem.ClippingConfiguration.Builder()
                                    .setStartPositionMs(clip.sourceIn).setEndPositionMs(clip.sourceIn + clip.duration).build()).build())
                        }
                    })
                    decoder.prepare()
                }
            }
            muted = args["muted"] == true
            fun volumes(key: String): Map<String, Float> = (args[key] as? Map<*, *>)?.entries?.associate {
                (it.key as String) to (it.value as Number).toFloat().coerceIn(0f, 1f)
            } ?: emptyMap()
            clipVolumes = volumes("clip_volumes")
            audioVolumes = volumes("audio_volumes")
            if (clips.isNotEmpty() && (changed || args["seek"] == true)) {
                val position = (args["position_ms"] as Number).toLong().coerceIn(0L, expectedStart)
                val index = clips.indexOfLast { position >= it.start }.coerceAtLeast(0)
                val clip = clips[index]
                // Avoid seeking past the final frame when the playhead is at the end.
                val local = (position - clip.start).coerceIn(0L, (clip.duration - 1).coerceAtLeast(0))
                player.seekTo(index, local)
            }
            if (audioChanged || changed || args["seek"] == true) {
                val position = (args["position_ms"] as Number).toLong().coerceIn(0L, expectedStart)
                for (lane in audioLanes) {
                    val index = lane.clips.indexOfLast { position >= it.start }.coerceAtLeast(0)
                    val clip = lane.clips[index]
                    lane.player.seekTo(index, (position - clip.start).coerceIn(0L, clip.duration - 1))
                    lane.lastCorrection = SystemClock.elapsedRealtime()
                    lane.player.setPlaybackSpeed(1f)
                }
            }
            requestedPlaying = args["playing"] == true && clips.isNotEmpty() && errorMessage == null
        } finally {
            updating = false
        }
        publish()
    }

    /** Wait for both decoders; never repeatedly seek a buffering player. */
    private fun synchronize() {
        if (synchronizing || updating || disposed) return
        synchronizing = true
        try {
            if (player.playbackState == Player.STATE_ENDED || errorMessage != null) requestedPlaying = false
            val ready = player.playbackState == Player.STATE_READY && audioLanes.all {
                it.player.playbackState == Player.STATE_READY || it.player.playbackState == Player.STATE_ENDED
            }
            val run = requestedPlaying && ready
            if (player.playWhenReady != run) player.playWhenReady = run
            for (lane in audioLanes) {
                val decoder = lane.player
                val active = run && decoder.playbackState != Player.STATE_ENDED
                if (decoder.playWhenReady != active) decoder.playWhenReady = active
                if (!active || !player.isPlaying || !decoder.isPlaying) continue
                val video = clips.getOrNull(player.currentMediaItemIndex) ?: continue
                val audio = lane.clips.getOrNull(decoder.currentMediaItemIndex) ?: continue
                val position = video.start + player.currentPosition
                val drift = position - (audio.start + decoder.currentPosition)
                val now = SystemClock.elapsedRealtime()
                if (kotlin.math.abs(drift) > 500 && now - lane.lastCorrection > 1500) {
                    val index = lane.clips.indexOfLast { position >= it.start }.coerceAtLeast(0)
                    val target = lane.clips[index]
                    decoder.seekTo(index, (position - target.start).coerceIn(0L, target.duration - 1))
                    lane.lastCorrection = now
                    decoder.setPlaybackSpeed(1f)
                } else if (now - lane.lastCorrection > 500) {
                    val speed = when { drift > 40 -> 1.02f; drift < -40 -> .98f; else -> 1f }
                    if (decoder.playbackParameters.speed != speed) decoder.setPlaybackSpeed(speed)
                }
            }
        } finally { synchronizing = false }
    }

    private fun publish() {
        if (disposed || updating || synchronizing) return
        synchronize()
        val clip = clips.getOrNull(player.currentMediaItemIndex)
        val position = if (player.playbackState == Player.STATE_ENDED) clips.lastOrNull()?.let { it.start + it.duration } ?: 0L
            else clip?.let { it.start + player.currentPosition.coerceIn(0L, it.duration) } ?: 0L
        val gap = clip?.isGap == true
        val videoVolume = if (muted || gap) 0f else clipVolumes[clip?.id] ?: 1f
        if (player.volume != videoVolume) player.volume = videoVolume
        for (lane in audioLanes) {
            val currentAudio = lane.clips.getOrNull(lane.player.currentMediaItemIndex)
            val volume = if (currentAudio?.isGap == true) 0f else audioVolumes[currentAudio?.id] ?: 1f
            if (lane.player.volume != volume) lane.player.volume = volume
        }
        // Hide the previous video during a silence source without detaching its surface.
        view.videoSurfaceView?.alpha = if (gap) 0f else 1f
        view.keepScreenOn = player.playWhenReady && player.playbackState != Player.STATE_ENDED && errorMessage == null
        val state = mapOf<String, Any?>(
            "revision" to revision, "position_ms" to position,
            "playing" to requestedPlaying,
            "has_frame" to (hasFrame || gap), "error" to errorMessage,
            "buffering" to (requestedPlaying && (player.playbackState == Player.STATE_BUFFERING ||
                audioLanes.any { it.player.playbackState == Player.STATE_BUFFERING })),
            "gap" to gap, "aspect_ratio" to aspectRatio)
        if (state != lastPublished) {
            lastPublished = state
            channel.invokeMethod("state", state)
        }
    }

    fun pause() {
        if (disposed) return
        requestedPlaying = false
        player.pause()
        audioLanes.forEach { it.player.pause() }
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
        audioLanes.forEach { it.player.release() }
        onDispose(this)
    }
}
