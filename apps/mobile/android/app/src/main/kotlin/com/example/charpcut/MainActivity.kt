package com.example.charpcut

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import android.util.AtomicFile
import android.content.Intent
import java.io.File
import java.io.FileNotFoundException
import java.util.concurrent.Executors

@androidx.annotation.OptIn(androidx.media3.common.util.UnstableApi::class)
class MainActivity : FlutterActivity() {
    private val projectIo = Executors.newSingleThreadExecutor()
    private var mediaLibrary: MediaLibrary? = null
    private var videoPreviewFactory: VideoPreviewFactory? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        videoPreviewFactory = VideoPreviewFactory(flutterEngine.dartExecutor.binaryMessenger).also {
            flutterEngine.platformViewsController.registry.registerViewFactory("charpcut/video-preview", it)
        }
        mediaLibrary = MediaLibrary(this, flutterEngine.dartExecutor.binaryMessenger)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "charpcut/projects")
            .setMethodCallHandler { call, result ->
                val slot = call.argument<String>("slot")
                if (slot != "draft" && slot != "saved" && slot != "library") {
                    result.error("invalid_slot", "Unknown project slot", null)
                    return@setMethodCallHandler
                }
                if (call.method != "read" && call.method != "write") {
                    result.notImplemented()
                    return@setMethodCallHandler
                }
                val json = call.argument<String>("json")
                if (call.method == "write" && json.isNullOrBlank()) {
                    result.error("invalid_json", "Project JSON is empty", null)
                    return@setMethodCallHandler
                }
                projectIo.execute {
                    try {
                        val directory = File(filesDir, "projects")
                        if (!directory.isDirectory && !directory.mkdirs()) {
                            error("Could not create project storage")
                        }
                        val file = AtomicFile(File(directory, "$slot.charpcut.json"))
                        if (call.method == "read") {
                            val text = try {
                                file.openRead().bufferedReader(Charsets.UTF_8).use { it.readText() }
                            } catch (error: FileNotFoundException) {
                                // Permission/read failures must not be mistaken for a missing draft.
                                if (file.baseFile.exists()) throw error
                                null
                            }
                            runOnUiThread { result.success(text) }
                        } else {
                            val stream = file.startWrite()
                            try {
                                stream.write(json!!.toByteArray(Charsets.UTF_8))
                                file.finishWrite(stream)
                            } catch (error: Exception) {
                                file.failWrite(stream)
                                throw error
                            }
                            runOnUiThread { result.success(null) }
                        }
                    } catch (error: Exception) {
                        runOnUiThread { result.error("project_io", error.message, null) }
                    }
                }
            }
    }

    override fun onDestroy() {
        videoPreviewFactory?.disposeAll()
        mediaLibrary?.dispose()
        projectIo.shutdown()
        super.onDestroy()
    }

    override fun onPause() {
        videoPreviewFactory?.pauseAll()
        super.onPause()
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        mediaLibrary?.onActivityResult(requestCode, resultCode, data)
    }
}
