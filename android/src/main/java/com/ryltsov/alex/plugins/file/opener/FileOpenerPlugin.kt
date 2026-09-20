package com.ryltsov.alex.plugins.file.opener

import android.content.ActivityNotFoundException
import android.content.ContentResolver
import android.content.Intent
import android.net.Uri
import android.webkit.MimeTypeMap
import androidx.core.content.FileProvider
import com.getcapacitor.Plugin
import com.getcapacitor.PluginCall
import com.getcapacitor.PluginMethod
import com.getcapacitor.annotation.CapacitorPlugin
import java.io.File

@CapacitorPlugin(name = "FileOpener")
public class FileOpenerPlugin : Plugin() {
    @PluginMethod
    public fun open(call: PluginCall) {
        // A call without a filePath has always ended in a NullPointerException rather than a rejection.
        val filePath = call.getString("filePath")!!
        val contentType = call.getString("contentType")
        val openWithDefault = call.getBoolean("openWithDefault", true) ?: true

        val fileUri = Uri.parse(filePath)

        if (filePath.startsWith("content://")) {
            try {
                activity.contentResolver.query(fileUri, null, null, null, null).use { cursor ->
                    if (cursor != null && cursor.count > 0) {
                        view(call, fileUri, if (isMissing(contentType)) getMimeType(fileUri) else contentType, openWithDefault)
                    } else {
                        call.reject("File not found", "9")
                    }
                }
            } catch (exception: ActivityNotFoundException) {
                call.reject("Activity not found: " + exception.message, "8", exception)
            } catch (exception: Exception) {
                call.reject(exception.localizedMessage, "1", exception)
            }
        } else {
            // An opaque URI has no path, which has always been a NullPointerException as well.
            val fileName = fileUri.path!!
            val file = File(fileName)
            if (file.exists()) {
                try {
                    val path = FileProvider.getUriForFile(activity.applicationContext, activity.packageName + ".file.opener.provider", file)
                    view(call, path, if (isMissing(contentType)) getMimeType(fileName) else contentType, openWithDefault)
                } catch (exception: ActivityNotFoundException) {
                    call.reject("Activity not found: " + exception.message, "8", exception)
                } catch (exception: Exception) {
                    call.reject(exception.localizedMessage, "1", exception)
                }
            } else {
                call.reject("File not found", "9")
            }
        }
    }

    private fun view(call: PluginCall, uri: Uri, contentType: String?, openWithDefault: Boolean) {
        val intent = Intent(Intent.ACTION_VIEW)
        intent.setDataAndType(uri, contentType)
        intent.setFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)

        if (openWithDefault) {
            activity.startActivity(intent)
        } else {
            activity.startActivity(Intent.createChooser(intent, "Open File in..."))
        }
        call.resolve()
    }

    private fun isMissing(contentType: String?): Boolean = contentType == null || contentType.trim { it <= ' ' }.isEmpty()

    private fun getMimeType(url: String): String? {
        val extension = MimeTypeMap.getFileExtensionFromUrl(url) ?: return null
        return MimeTypeMap.getSingleton().getMimeTypeFromExtension(extension)
    }

    private fun getMimeType(uri: Uri): String? = if (uri.scheme == ContentResolver.SCHEME_CONTENT) {
        activity.contentResolver.getType(uri)
    } else {
        getMimeType(uri.toString())
    }
}
