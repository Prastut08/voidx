package com.cyclonex.app

import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothManager
import android.bluetooth.le.*
import android.content.Context
import android.os.ParcelUuid
import android.util.Log
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import org.json.JSONArray
import org.json.JSONObject
import java.nio.charset.StandardCharsets
import java.util.*
import java.util.concurrent.ConcurrentHashMap

/**
 * Offline Emergency Store-Carry-Forward Relay Companion Module for CycloneX.
 * Uses Bluetooth Low Energy Advertising & Scanning for offline D2D emergency message propagation.
 */
class OfflineEmergencyRelay(private val context: Context) : MethodChannel.MethodCallHandler {
    companion object {
        const val CHANNEL_NAME = "com.example.cyclonex/offline_relay"
        const val TAG = "CycloneX_Relay"
        val RELAY_SERVICE_UUID: UUID = UUID.fromString("0000FE2C-0000-1000-8000-00805F9B34FB")
        val SERVICE_DATA_UUID: UUID = UUID.fromString("0000FE2D-0000-1000-8000-00805F9B34FB")
    }

    private var channel: MethodChannel? = null
    private var bluetoothAdapter: BluetoothAdapter? = null
    private var bleAdvertiser: BluetoothLeAdvertiser? = null
    private var bleScanner: BluetoothLeScanner? = null
    
    private val localMessages = ConcurrentHashMap<String, JSONObject>()
    private val discoveredRelayDevices = ConcurrentHashMap<String, Long>()
    
    private var isRelaying = false

    fun register(flutterEngine: FlutterEngine) {
        channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL_NAME)
        channel?.setMethodCallHandler(this)
        
        val bluetoothManager = context.getSystemService(Context.BLUETOOTH_SERVICE) as? BluetoothManager
        bluetoothAdapter = bluetoothManager?.adapter
        bleAdvertiser = bluetoothAdapter?.bluetoothLeAdvertiser
        bleScanner = bluetoothAdapter?.bluetoothLeScanner
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "startRelay" -> {
                val success = startBleRelay()
                result.success(success)
            }
            "stopRelay" -> {
                stopBleRelay()
                result.success(true)
            }
            "queueEmergencyMessage" -> {
                val jsonStr = call.argument<String>("message")
                if (jsonStr != null) {
                    val jsonObj = JSONObject(jsonStr)
                    val id = jsonObj.optString("sos_id", UUID.randomUUID().toString())
                    localMessages[id] = jsonObj
                    result.success(true)
                } else {
                    result.error("INVALID_ARGS", "Missing message string", null)
                }
            }
            "getQueuedMessages" -> {
                val array = JSONArray()
                localMessages.values.forEach { array.put(it) }
                result.success(array.toString())
            }
            "clearSyncedMessages" -> {
                val ids = call.argument<List<String>>("ids")
                ids?.forEach { localMessages.remove(it) }
                result.success(true)
            }
            "getDiscoveredRelayCount" -> {
                result.success(discoveredRelayDevices.size)
            }
            else -> result.notImplemented()
        }
    }

    private fun startBleRelay(): Boolean {
        if (bluetoothAdapter == null || !bluetoothAdapter!!.isEnabled) {
            Log.w(TAG, "Bluetooth not available or disabled")
            return false
        }

        try {
            // BLE Advertising for pending emergency packet
            bleAdvertiser = bluetoothAdapter?.bluetoothLeAdvertiser
            val advertiseSettings = AdvertiseSettings.Builder()
                .setAdvertiseMode(AdvertiseSettings.ADVERTISE_MODE_LOW_LATENCY)
                .setConnectable(false)
                .setTimeout(0)
                .setTxPowerLevel(AdvertiseSettings.ADVERTISE_TX_POWER_HIGH)
                .build()

            val advertiseData = AdvertiseData.Builder()
                .setIncludeDeviceName(false)
                .addServiceUuid(ParcelUuid(RELAY_SERVICE_UUID))
                .addServiceData(ParcelUuid(SERVICE_DATA_UUID), "SOS_ACTIVE".toByteArray(StandardCharsets.UTF_8))
                .build()

            bleAdvertiser?.startAdvertising(advertiseSettings, advertiseData, object : AdvertiseCallback() {
                override fun onStartSuccess(settingsInEffect: AdvertiseSettings?) {
                    Log.i(TAG, "CycloneX Offline Emergency Relay Advertising active")
                }
                override fun onStartFailure(errorCode: Int) {
                    Log.e(TAG, "Relay Advertising failed: $errorCode")
                }
            })

            // BLE Scanning to discover nearby mesh peer relays
            bleScanner = bluetoothAdapter?.bluetoothLeScanner
            val scanFilters = listOf(
                ScanFilter.Builder().setServiceUuid(ParcelUuid(RELAY_SERVICE_UUID)).build()
            )
            val scanSettings = ScanSettings.Builder()
                .setScanMode(ScanSettings.SCAN_MODE_LOW_LATENCY)
                .build()

            bleScanner?.startScan(scanFilters, scanSettings, object : ScanCallback() {
                override fun onScanResult(callbackType: Int, result: ScanResult?) {
                    result?.device?.address?.let { addr ->
                        val isNew = !discoveredRelayDevices.containsKey(addr)
                        discoveredRelayDevices[addr] = System.currentTimeMillis()
                        if (isNew) {
                            Log.i(TAG, "Discovered nearby emergency relay peer: $addr")
                            channel?.invokeMethod("onRelayPeerFound", mapOf("peerId" to addr, "peerCount" to discoveredRelayDevices.size))
                        }
                    }
                }
            })

            isRelaying = true
            return true
        } catch (e: Exception) {
            Log.e(TAG, "Error starting BLE Relay: ${e.message}")
            return false
        }
    }

    private fun stopBleRelay() {
        try {
            bleAdvertiser?.stopAdvertising(object : AdvertiseCallback() {})
            bleScanner?.stopScan(object : ScanCallback() {})
            isRelaying = false
        } catch (e: Exception) {
            Log.w(TAG, "Error stopping relay: ${e.message}")
        }
    }
}
