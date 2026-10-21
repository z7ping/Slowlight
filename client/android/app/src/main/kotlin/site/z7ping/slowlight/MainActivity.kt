package site.z7ping.slowlight

import android.content.Intent
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "site.z7ping.slowlight/diagnostics")
            .setMethodCallHandler { call, result ->
                if (call.method != "shareLog") {
                    result.notImplemented()
                    return@setMethodCallHandler
                }
                try {
                    val path = call.argument<String>("path")
                        ?: throw IllegalArgumentException("缺少日志文件")
                    val allowed = File(cacheDir, "diagnostics").canonicalFile
                    val file = File(path).canonicalFile
                    if (!file.isFile || file.parentFile != allowed) {
                        throw SecurityException("不允许导出该文件")
                    }
                    val uri = FileProvider.getUriForFile(
                        this, "${packageName}.diagnostics", file
                    )
                    val intent = Intent(Intent.ACTION_SEND).apply {
                        type = "text/plain"
                        putExtra(Intent.EXTRA_STREAM, uri)
                        addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                    }
                    startActivity(Intent.createChooser(intent, "导出诊断日志"))
                    result.success(null)
                } catch (error: Exception) {
                    result.error("SHARE_LOG_FAILED", "无法分享诊断日志", null)
                }
            }
    }
}
