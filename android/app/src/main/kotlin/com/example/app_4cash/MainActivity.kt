package com.example.app_4cash

import android.content.Context
import android.hardware.usb.UsbConstants
import android.hardware.usb.UsbDeviceConnection
import android.hardware.usb.UsbEndpoint
import android.hardware.usb.UsbInterface
import android.hardware.usb.UsbManager
import androidx.annotation.NonNull
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.Executors // THÊM IMPORT NÀY

class MainActivity: FlutterActivity() {
    private val CHANNEL = "com.example.app_4cash/usb_printer"
    private var usbManager: UsbManager? = null
    
    // TẠO HÀNG ĐỢI THỰC THI ĐƠN LUỒNG (Tuần tự 100%)
    private val printExecutor = Executors.newSingleThreadExecutor()

    override fun configureFlutterEngine(@NonNull flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        
        usbManager = getSystemService(Context.USB_SERVICE) as UsbManager

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "getDeviceList" -> {
                    val devices = usbManager?.deviceList?.values?.map { device ->
                        mapOf(
                            "identifier" to device.deviceName,
                            "vendorId" to device.vendorId,
                            "productId" to device.productId,
                            "productName" to (device.productName ?: "USB Device"),
                            "deviceId" to device.deviceId
                        )
                    } ?: emptyList()
                    result.success(devices)
                }
                "printData" -> {
                    val identifier = call.argument<String>("identifier")
                    val data = call.argument<ByteArray>("data")
                    
                    if (identifier == null || data == null) {
                        result.error("INVALID_ARGS", "Thiếu tham số", null)
                        return@setMethodCallHandler
                    }
                    
                    // THAY THẾ Thread { }.start() BẰNG executor.execute { }
                    // Việc này đảm bảo Tem vào trước -> In xong Tem -> Mới in Bill
                    printExecutor.execute {
                        try {
                            val printResult = connectAndPrint(identifier, data)
                            runOnUiThread {
                                if (printResult) result.success(true)
                                else result.error("PRINT_FAILED", "Lỗi kết nối", null)
                            }
                        } catch (e: Exception) {
                            runOnUiThread { result.error("EXCEPTION", e.message, null) }
                        }
                    }
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun connectAndPrint(identifier: String, data: ByteArray): Boolean {
        var usbConnection: UsbDeviceConnection? = null
        var usbInterface: UsbInterface? = null

        try {
            val device = usbManager?.deviceList?.values?.find { it.deviceName == identifier }
                ?: return false

            if (!usbManager!!.hasPermission(device)) {
                return false 
            }

            usbConnection = usbManager!!.openDevice(device) ?: return false
            
            // Logic tìm cổng OUT (giữ nguyên)
            var targetEndpoint: UsbEndpoint? = null
            for (i in 0 until device.interfaceCount) {
                val iface = device.getInterface(i)
                for (j in 0 until iface.endpointCount) {
                    val ep = iface.getEndpoint(j)
                    if (ep.direction == UsbConstants.USB_DIR_OUT) {
                        usbInterface = iface
                        targetEndpoint = ep
                        break
                    }
                }
                if (targetEndpoint != null) break
            }

            if (targetEndpoint == null || usbInterface == null) {
                usbConnection.close()
                return false
            }

            usbConnection.claimInterface(usbInterface, true)

            val chunkSize = 4096
            var offset = 0
            while (offset < data.size) {
                val length = Math.min(chunkSize, data.size - offset)
                val chunk = data.copyOfRange(offset, offset + length)
                
                val transferred = usbConnection.bulkTransfer(targetEndpoint, chunk, length, 3000)
                if (transferred < 0) break
                
                offset += length
                // Giảm delay xuống tối thiểu
                Thread.sleep(1) 
            }

            usbConnection.releaseInterface(usbInterface)
            usbConnection.close()
            
            // Thêm delay nhỏ sau khi đóng để đảm bảo cổng USB nhả ra hoàn toàn cho lệnh sau
            Thread.sleep(50) 
            
            return offset >= data.size

        } catch (e: Exception) {
            e.printStackTrace()
            usbConnection?.close()
            return false
        }
    }
}