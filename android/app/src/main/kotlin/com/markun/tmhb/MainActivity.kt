package com.markun.tmhb

import android.content.Context
import android.net.wifi.WifiManager
import android.os.Handler
import android.os.Looper
import android.system.ErrnoException
import android.system.Os
import android.system.OsConstants
import android.system.StructPollfd
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import java.io.FileDescriptor
import java.io.FileInputStream
import java.io.FileOutputStream
import java.net.InetAddress
import java.util.concurrent.Executors

class MainActivity : FlutterActivity() {
    private var multicastLock: WifiManager.MulticastLock? = null
    private var akeEventSink: EventChannel.EventSink? = null
    private val akeConnections = mutableMapOf<Int, AkeSocketConnection>()
    private val akeExecutor = Executors.newCachedThreadPool()
    private val mainHandler = Handler(Looper.getMainLooper())

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, MULTICAST_LOCK_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "acquire" -> {
                        acquireMulticastLock()
                        result.success(null)
                    }
                    "release" -> {
                        releaseMulticastLock()
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, AKE_SOCKET_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "connect" -> {
                        val id = call.argument<Int>("id")!!
                        val host = call.argument<String>("host")!!
                        val port = call.argument<Int>("port")!!
                        val connection = AkeSocketConnection(id) { event -> emitAkeEvent(event) }
                        synchronized(akeConnections) { akeConnections[id] = connection }
                        akeExecutor.execute {
                            try {
                                connection.connect(host, port, 10_000)
                                mainHandler.post { result.success(null) }
                            } catch (e: Exception) {
                                synchronized(akeConnections) { akeConnections.remove(id) }
                                mainHandler.post {
                                    result.error("connect_failed", e.message, null)
                                }
                            }
                        }
                    }
                    "send" -> {
                        val id = call.argument<Int>("id")!!
                        val data = call.argument<ByteArray>("data")!!
                        val connection = synchronized(akeConnections) { akeConnections[id] }
                        if (connection != null) {
                            akeExecutor.execute { connection.send(data) }
                        }
                        result.success(null)
                    }
                    "close" -> {
                        val id = call.argument<Int>("id")!!
                        val connection = synchronized(akeConnections) { akeConnections.remove(id) }
                        connection?.close()
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
        EventChannel(flutterEngine.dartExecutor.binaryMessenger, AKE_SOCKET_EVENTS_CHANNEL)
            .setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    akeEventSink = events
                }

                override fun onCancel(arguments: Any?) {
                    akeEventSink = null
                }
            })
    }

    private fun emitAkeEvent(event: Map<String, Any?>) {
        mainHandler.post { akeEventSink?.success(event) }
    }

    // SSDP M-SEARCH responses arrive as Wi-Fi multicast; without this
    // lock the driver may filter them out (plan 17).
    private fun acquireMulticastLock() {
        if (multicastLock == null) {
            val wifi = applicationContext.getSystemService(Context.WIFI_SERVICE) as WifiManager
            multicastLock = wifi.createMulticastLock("torne-mobile-hb-ssdp").apply {
                setReferenceCounted(false)
            }
        }
        if (multicastLock?.isHeld != true) {
            multicastLock?.acquire()
        }
    }

    private fun releaseMulticastLock() {
        if (multicastLock?.isHeld == true) {
            multicastLock?.release()
        }
    }

    companion object {
        private const val MULTICAST_LOCK_CHANNEL = "com.markun.tmhb/multicast_lock"
        private const val AKE_SOCKET_CHANNEL = "com.markun.tmhb/ake_socket"
        private const val AKE_SOCKET_EVENTS_CHANNEL = "com.markun.tmhb/ake_socket_events"
    }
}

/// One native AKE socket (plan 28): a BSD socket with IP TTL 3 and
/// TCP_NODELAY set via setsockopt before connect (the DTCP-IP
/// proximity requirement the reference client implements), with
/// blocking I/O on worker threads afterwards.
private class AkeSocketConnection(
    private val id: Int,
    private val emit: (Map<String, Any?>) -> Unit,
) {
    private var fd: FileDescriptor? = null
    private var input: FileInputStream? = null
    private var output: FileOutputStream? = null

    @Volatile
    private var closed = false

    fun connect(host: String, port: Int, timeoutMs: Int) {
        val descriptor = Os.socket(OsConstants.AF_INET, OsConstants.SOCK_STREAM, 0)
        try {
            Os.setsockoptInt(descriptor, OsConstants.IPPROTO_IP, OsConstants.IP_TTL, 3)
            Os.setsockoptInt(descriptor, OsConstants.IPPROTO_TCP, OsConstants.TCP_NODELAY, 1)
            val address = InetAddress.getByName(host)
            val flags = Os.fcntlInt(descriptor, OsConstants.F_GETFL, 0)
            Os.fcntlInt(descriptor, OsConstants.F_SETFL, flags or OsConstants.O_NONBLOCK)
            var inProgress = false
            try {
                Os.connect(descriptor, address, port)
            } catch (e: ErrnoException) {
                if (e.errno != OsConstants.EINPROGRESS) throw e
                inProgress = true
            }
            if (inProgress) {
                val pollFd = StructPollfd().apply {
                    fd = descriptor
                    events = OsConstants.POLLOUT.toShort()
                }
                val ready = Os.poll(arrayOf(pollFd), timeoutMs)
                if (ready <= 0) {
                    throw ErrnoException("connect", OsConstants.ETIMEDOUT)
                }
                val error = Os.getsockoptInt(
                    descriptor,
                    OsConstants.SOL_SOCKET,
                    OsConstants.SO_ERROR,
                )
                if (error != 0) throw ErrnoException("connect", error)
            }
            Os.fcntlInt(descriptor, OsConstants.F_SETFL, flags)
        } catch (e: Exception) {
            try {
                Os.close(descriptor)
            } catch (_: Exception) {
            }
            throw e
        }
        fd = descriptor
        input = FileInputStream(descriptor)
        output = FileOutputStream(descriptor)
        Thread { readLoop() }.apply { isDaemon = true }.start()
    }

    private fun readLoop() {
        val buffer = ByteArray(16384)
        try {
            while (!closed) {
                val count = input!!.read(buffer)
                if (count > 0) {
                    emit(
                        mapOf(
                            "id" to id,
                            "kind" to "data",
                            "data" to buffer.copyOf(count),
                        ),
                    )
                } else if (count < 0) {
                    if (!closed) emit(mapOf("id" to id, "kind" to "done"))
                    return
                }
            }
        } catch (e: Exception) {
            if (!closed) {
                emit(
                    mapOf(
                        "id" to id,
                        "kind" to "error",
                        "message" to (e.message ?: "socket error"),
                    ),
                )
            }
        }
    }

    fun send(data: ByteArray) {
        val out = output ?: return
        synchronized(out) {
            try {
                out.write(data)
                out.flush()
            } catch (e: Exception) {
                if (!closed) {
                    emit(
                        mapOf(
                            "id" to id,
                            "kind" to "error",
                            "message" to (e.message ?: "send failed"),
                        ),
                    )
                }
            }
        }
    }

    fun close() {
        closed = true
        // Best effort: closing the descriptor and the streams wakes
        // the read loop in practice; a lingering reader exits when
        // the peer closes and its events are dropped by the Dart
        // side, which has already forgotten this connection.
        try {
            input?.close()
        } catch (_: Exception) {
        }
        try {
            output?.close()
        } catch (_: Exception) {
        }
        val descriptor = fd
        fd = null
        if (descriptor != null) {
            try {
                Os.close(descriptor)
            } catch (_: Exception) {
            }
        }
    }
}
