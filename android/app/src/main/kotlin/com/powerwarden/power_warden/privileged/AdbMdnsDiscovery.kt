package com.powerwarden.power_warden.privileged

import android.content.Context
import android.net.nsd.NsdManager
import android.net.nsd.NsdServiceInfo
import android.os.Handler
import android.os.Looper
import android.util.Log

/**
 * Discovers Wireless Debugging pairing and connection ports on localhost / local network
 * using Android's native Network Service Discovery (mDNS).
 * Service types:
 * - "_adb-tls-pairing._tcp" -> Auto-discovers the dynamic pairing port!
 * - "_adb-tls-connect._tcp" -> Auto-discovers the active connection port!
 */
class AdbMdnsDiscovery(private val context: Context) {

    private val nsdManager = context.getSystemService(Context.NSD_SERVICE) as NsdManager
    private val mainHandler = Handler(Looper.getMainLooper())

    var discoveredPairingPort: Int? = null
        private set
    var discoveredConnectPort: Int? = null
        private set

    var onPairingPortDiscovered: ((Int) -> Unit)? = null
    var onConnectPortDiscovered: ((Int) -> Unit)? = null

    private var pairingDiscoveryListener: NsdManager.DiscoveryListener? = null
    private var connectDiscoveryListener: NsdManager.DiscoveryListener? = null

    fun startDiscovery() {
        startPairingDiscovery()
        startConnectDiscovery()
    }

    private fun startPairingDiscovery() {
        if (pairingDiscoveryListener != null) return

        pairingDiscoveryListener = object : NsdManager.DiscoveryListener {
            override fun onDiscoveryStarted(regType: String) {}

            override fun onServiceFound(serviceInfo: NsdServiceInfo) {
                if (serviceInfo.serviceType.contains("_adb-tls-pairing")) {
                    resolveService(serviceInfo) { port ->
                        discoveredPairingPort = port
                        mainHandler.post {
                            onPairingPortDiscovered?.invoke(port)
                        }
                    }
                }
            }

            override fun onServiceLost(serviceInfo: NsdServiceInfo) {}
            override fun onDiscoveryStopped(serviceType: String) {}
            override fun onStartDiscoveryFailed(serviceType: String, errorCode: Int) {
                pairingDiscoveryListener = null
            }
            override fun onStopDiscoveryFailed(serviceType: String, errorCode: Int) {}
        }

        try {
            nsdManager.discoverServices("_adb-tls-pairing._tcp", NsdManager.PROTOCOL_DNS_SD, pairingDiscoveryListener)
        } catch (_: Exception) {
            pairingDiscoveryListener = null
        }
    }

    private fun startConnectDiscovery() {
        if (connectDiscoveryListener != null) return

        connectDiscoveryListener = object : NsdManager.DiscoveryListener {
            override fun onDiscoveryStarted(regType: String) {}

            override fun onServiceFound(serviceInfo: NsdServiceInfo) {
                if (serviceInfo.serviceType.contains("_adb-tls-connect")) {
                    resolveService(serviceInfo) { port ->
                        discoveredConnectPort = port
                        mainHandler.post {
                            onConnectPortDiscovered?.invoke(port)
                        }
                    }
                }
            }

            override fun onServiceLost(serviceInfo: NsdServiceInfo) {}
            override fun onDiscoveryStopped(serviceType: String) {}
            override fun onStartDiscoveryFailed(serviceType: String, errorCode: Int) {
                connectDiscoveryListener = null
            }
            override fun onStopDiscoveryFailed(serviceType: String, errorCode: Int) {}
        }

        try {
            nsdManager.discoverServices("_adb-tls-connect._tcp", NsdManager.PROTOCOL_DNS_SD, connectDiscoveryListener)
        } catch (_: Exception) {
            connectDiscoveryListener = null
        }
    }

    private fun resolveService(serviceInfo: NsdServiceInfo, onResolved: (Int) -> Unit) {
        nsdManager.resolveService(serviceInfo, object : NsdManager.ResolveListener {
            override fun onResolveFailed(serviceInfo: NsdServiceInfo, errorCode: Int) {}

            override fun onServiceResolved(serviceInfo: NsdServiceInfo) {
                val port = serviceInfo.port
                if (port > 0) {
                    onResolved(port)
                }
            }
        })
    }

    fun stopDiscovery() {
        pairingDiscoveryListener?.let {
            try { nsdManager.stopServiceDiscovery(it) } catch (_: Exception) {}
            pairingDiscoveryListener = null
        }
        connectDiscoveryListener?.let {
            try { nsdManager.stopServiceDiscovery(it) } catch (_: Exception) {}
            connectDiscoveryListener = null
        }
    }
}
