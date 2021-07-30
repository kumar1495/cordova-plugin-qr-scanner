import Foundation	
import AVFoundation

@objc(QRScannerPlugin) class QRScannerPlugin : CDVPlugin,AVCaptureMetadataOutputObjectsDelegate {
    
    var captureSession: AVCaptureSession?
    var captureVideoPreviewLayer: AVCaptureVideoPreviewLayer!
    var cameraView: CameraView!
    var command: CDVInvokedUrlCommand?
    
    class CameraView: UIView {
        var videoPreviewLayer:AVCaptureVideoPreviewLayer?
        func interfaceOrientationToVideoOrientation(_ orientation : UIInterfaceOrientation) -> AVCaptureVideoOrientation {
            switch (orientation) {
            case UIInterfaceOrientation.portrait:
                return AVCaptureVideoOrientation.portrait;
            case UIInterfaceOrientation.portraitUpsideDown:
                return AVCaptureVideoOrientation.portraitUpsideDown;
            case UIInterfaceOrientation.landscapeLeft:
                return AVCaptureVideoOrientation.landscapeLeft;
            case UIInterfaceOrientation.landscapeRight:
                return AVCaptureVideoOrientation.landscapeRight;
            default:
                return AVCaptureVideoOrientation.portraitUpsideDown;
            }
        }
        
        override func layoutSubviews() {
            super.layoutSubviews();
            if let sublayers = self.layer.sublayers {
                for layer in sublayers {
                    layer.frame = self.bounds;
                }
            }
            
            self.videoPreviewLayer?.connection?.videoOrientation = interfaceOrientationToVideoOrientation(UIApplication.shared.statusBarOrientation);
        }
        
        
        func addPreviewLayer(_ previewLayer:AVCaptureVideoPreviewLayer?) {
            previewLayer!.videoGravity = AVLayerVideoGravity.resizeAspectFill
            previewLayer!.frame = self.bounds
            self.layer.addSublayer(previewLayer!)
            self.videoPreviewLayer = previewLayer;
        }
        
        func removePreviewLayer() {
            if self.videoPreviewLayer != nil {
                self.videoPreviewLayer!.removeFromSuperlayer()
                self.videoPreviewLayer = nil
            }
        }
    }
    
    private func backgroundThread(delay: Double = 0.0, background: (() -> Void)? = nil, completion: (() -> Void)? = nil) {
        if #available(iOS 8.0, *) {
            DispatchQueue.global(qos: DispatchQoS.QoSClass.userInitiated).async {
                if (background != nil) {
                    background!()
                }
                DispatchQueue.main.asyncAfter(deadline: DispatchTime.now() + delay * Double(NSEC_PER_SEC)) {
                    if(completion != nil){
                        completion!()
                    }
                }
            }
        } else {
            if(background != nil){
                background!()
            }
            if(completion != nil){
                completion!()
            }
        }
    }
    
    
    private func prepScanner(_ command: CDVInvokedUrlCommand) -> Bool {
        let pluginResult:CDVPluginResult = CDVPluginResult.init(status: CDVCommandStatus_ERROR)
        self.captureSession = AVCaptureSession()
        if let captureSession = self.captureSession {
            let status = AVCaptureDevice.authorizationStatus(for: AVMediaType.video)
            if (status == AVAuthorizationStatus.restricted) {
                self.commandDelegate.send(pluginResult, callbackId: command.callbackId)
                return false
            } else if status == AVAuthorizationStatus.denied {
                self.commandDelegate.send(pluginResult, callbackId: command.callbackId)
                return false
            }
            self.cameraView.backgroundColor = UIColor.clear
            self.webView!.superview!.insertSubview(self.cameraView, belowSubview: self.webView!)
            guard let videoCaptureDevice = AVCaptureDevice.default(for: AVMediaType.video) else {
                self.commandDelegate.send(pluginResult, callbackId: command.callbackId)
                return false
            }
            let videoInput: AVCaptureDeviceInput
            do {
                videoInput = try AVCaptureDeviceInput(device: videoCaptureDevice)
            } catch let error {
                print(error)
                self.commandDelegate.send(pluginResult, callbackId: command.callbackId)
                return false
            }
            if captureSession.canAddInput(videoInput) {
                captureSession.addInput(videoInput)
            } else {
                self.commandDelegate.send(pluginResult, callbackId: command.callbackId)
                return false
            }
            let metadataOutput = AVCaptureMetadataOutput()
            if captureSession.canAddOutput(metadataOutput) {
                captureSession.addOutput(metadataOutput)
                metadataOutput.setMetadataObjectsDelegate(self, queue: DispatchQueue.main)
                metadataOutput.metadataObjectTypes = [AVMetadataObject.ObjectType.qr]
                self.captureVideoPreviewLayer = AVCaptureVideoPreviewLayer(session: captureSession)
                self.cameraView.addPreviewLayer(captureVideoPreviewLayer)
                captureSession.startRunning();
                return true
            } else {
                self.commandDelegate.send(pluginResult, callbackId: command.callbackId)
                return false
            }
        }
        self.commandDelegate.send(pluginResult, callbackId: command.callbackId)
        return false
    }
    
    
    override func pluginInitialize() {
        super.pluginInitialize()
        self.cameraView = CameraView(frame: CGRect(x: 0, y: 0, width: UIScreen.main.bounds.width, height: UIScreen.main.bounds.height))
        self.cameraView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
    }
    
    func metadataOutput(_ output: AVCaptureMetadataOutput, didOutput metadataObjects: [AVMetadataObject], from connection: AVCaptureConnection) {
        if let first = metadataObjects.first {
            guard let readableObject = first as? AVMetadataMachineReadableCodeObject else { return }
            guard let stringyfiedValue = readableObject.stringValue else { return }
            print("QRCode - \(stringyfiedValue)")
            if let command = self.command {
                self.stopScanning()
                let pluginResult:CDVPluginResult = CDVPluginResult.init(status: CDVCommandStatus_OK, messageAs: stringyfiedValue)
                self.commandDelegate.send(pluginResult, callbackId: command.callbackId)
            }
        }
    }
    
    private func stopScanning() {
        if let captureSession = self.captureSession {
            captureSession.stopRunning()
            self.cameraView.removePreviewLayer()
            self.captureVideoPreviewLayer = nil
            self.captureSession = nil
            self.captureVideoPreviewLayer = nil
        }
    }
    
    private func startScanning(_ command: CDVInvokedUrlCommand) {
        self.backgroundThread(delay: 0, completion: {
            if(self.prepScanner(command)) {
                self.webView?.isOpaque = false
                self.webView?.backgroundColor = UIColor.clear
            }
        })
    }
    
    @objc(qrScanner:)
    func qrScanner (_ command: CDVInvokedUrlCommand) {
        let methodName = command.arguments[0] as! String
        if methodName == "startScanner" {
            self.startScanner(command)
        } else if methodName == "stopScanner" {
            self.stopScanner(command)
        }
    }
    
    @objc(startScanner:)
    func startScanner(_ command: CDVInvokedUrlCommand) {
        var pluginResult:CDVPluginResult = CDVPluginResult.init(status: CDVCommandStatus_ERROR)
        let startScanner = command.arguments[0] as? String ?? ""
        let screenTitle = command.arguments[1] as? String ?? "Scan QR Code."
        let displayText = command.arguments[2] as? String ?? "Point your phone to the QR code to scan it"
        let displayTextColor = command.arguments[3] as? String ?? "0b0b0b"
        let buttonText = command.arguments[4] as? String ?? "I don't have a QR Code"
        let showButton = command.arguments[5] as? Bool ?? false
        let isRtl = command.arguments[6] as? Bool ?? false
        self.stopScanning()
        let status = AVCaptureDevice.authorizationStatus(for: AVMediaType.video)
        self.command = command
        if (status == AVAuthorizationStatus.notDetermined) {
            AVCaptureDevice.requestAccess(for: AVMediaType.video, completionHandler: { (granted) -> Void in
                self.startScanning(command)
            })
        } else {
            self.startScanning(command)
        }
    }
    
    @objc(stopScanner:)
    func stopScanner(_ command: CDVInvokedUrlCommand) {
        let pluginResult:CDVPluginResult = CDVPluginResult.init(status: CDVCommandStatus_OK)
        backgroundThread(delay: 0, background: {
            self.stopScanning()
        }, completion: {
            self.commandDelegate.send(pluginResult, callbackId: command.callbackId)
        })
    }
}

