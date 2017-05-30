//
//  CameraController.swift
//  AV Foundation
//
//  Created by Jimmy Hoang on 5/30/17.
//  Copyright © 2017 Pranjal Satija. All rights reserved.
//

import Foundation
import AVFoundation
import UIKit

enum CameraControllerError: Swift.Error {
    case captureSessionAlreadyRunning
    case captureSessionIsMissing
    case inputsAreInvalid
    case invalidOperation
    case noCamerasAvailable
    case unknown
}

enum CameraPosition {
    case front
    case rear
}

class CameraController: NSObject {
    
    var captureSession: AVCaptureSession?
    
    var frontCamera: AVCaptureDevice?
    var rearCamera: AVCaptureDevice?
    
    var currentCameraPosition: CameraPosition?
    var frontCameraInput: AVCaptureDeviceInput?
    var rearCameraInput: AVCaptureDeviceInput?
    
    var photoOutput: AVCapturePhotoOutput?
    
    var previewLayer: AVCaptureVideoPreviewLayer?
    
    var flashMode = AVCaptureFlashMode.off
    
    var photoCaptureCompletionBlock: ((UIImage?, Error?) -> Void)?
    
    func prepare(completionHandler: @escaping (Error?) -> ()) {
        
        DispatchQueue(label: "prepare").async {
            do {
                self.createCaptureSession()
                try self.configCaptureDevice()
                try self.configDeviceInputs()
                try self.configPhotoOutput()
            } catch {
                DispatchQueue.main.async {
                    completionHandler(error)
                }
                
                return
            }
            
            DispatchQueue.main.async {
                completionHandler(nil)
            }
        }
    }
    
    func displayPreview(on view: UIView) throws {
        guard let captureSession = self.captureSession, captureSession.isRunning else { throw CameraControllerError.captureSessionIsMissing }
        
        self.previewLayer = AVCaptureVideoPreviewLayer(session: captureSession)
        self.previewLayer?.videoGravity = AVLayerVideoGravityResizeAspectFill
        self.previewLayer?.connection.videoOrientation = .portrait
        
        view.layer.insertSublayer(self.previewLayer!, at: 0)
        self.previewLayer?.frame = view.frame
    }
}

extension CameraController {
    func createCaptureSession() {
        self.captureSession = AVCaptureSession()
    }
    
    func configCaptureDevice() throws {
        let session = AVCaptureDeviceDiscoverySession(deviceTypes: [.builtInWideAngleCamera], mediaType: AVMediaTypeVideo, position: .unspecified)
        
        guard let cameras = (session?.devices.flatMap{ $0 }), !cameras.isEmpty else { throw CameraControllerError.noCamerasAvailable }
        
        for camera in cameras {
            if camera.position == .front {
                self.frontCamera = camera
            }
            
            if camera.position == .back {
                self.rearCamera = camera
                
                try camera.lockForConfiguration()
                camera.focusMode = .continuousAutoFocus
                camera.unlockForConfiguration()
            }
        }
    }
    
    func configDeviceInputs() throws {
        guard let captureSession = self.captureSession else { throw CameraControllerError.captureSessionIsMissing }
        
        if let rearCamera = self.rearCamera {
            self.rearCameraInput = try AVCaptureDeviceInput(device: rearCamera)
            
            if captureSession.canAddInput(self.rearCameraInput!) {
                captureSession.addInput(self.rearCameraInput!)
                self.currentCameraPosition = .rear
            }
        } else if let frontCamera = self.frontCamera {
            self.frontCameraInput = try AVCaptureDeviceInput(device: frontCamera)
            
            if captureSession.canAddInput(self.frontCameraInput!) {
                captureSession.addInput(self.frontCameraInput!)
                self.currentCameraPosition = .front
            }
        } else {
            throw CameraControllerError.noCamerasAvailable
        }
    }
    
    func configPhotoOutput() throws {
        guard let captureSession = self.captureSession else { throw CameraControllerError.captureSessionIsMissing }
        
        self.photoOutput = AVCapturePhotoOutput()
        self.photoOutput?.setPreparedPhotoSettingsArray([AVCapturePhotoSettings(format: [AVVideoCodecKey: AVVideoCodecJPEG])], completionHandler: nil)
        
        if captureSession.canAddOutput(self.photoOutput) {
            captureSession.addOutput(self.photoOutput)
            
            captureSession.startRunning()
        }
    }
}

extension CameraController {
    func switchCameras() throws {
        guard let currentCameraPosition = currentCameraPosition, let captureSession = self.captureSession, captureSession.isRunning else { throw CameraControllerError.captureSessionIsMissing }
        
        captureSession.beginConfiguration()
        
        switch currentCameraPosition {
        case .front:
            try switchRearCamera()
        case .rear:
            try switchFrontCamera()
        }
        
        captureSession.commitConfiguration()
    }
    
    func switchFrontCamera() throws {
        guard let inputs = captureSession?.inputs as? [AVCaptureInput], let rearCameraInput = self.rearCameraInput, inputs.contains(rearCameraInput), let frontCamera = self.frontCamera else { throw CameraControllerError.invalidOperation }
        
        self.frontCameraInput = try AVCaptureDeviceInput(device: frontCamera)
        captureSession?.removeInput(rearCameraInput)
        
        if captureSession!.canAddInput(self.frontCameraInput!) {
            captureSession?.addInput(self.frontCameraInput)
            
            self.currentCameraPosition = .front
        } else {
            throw CameraControllerError.invalidOperation
        }
    }
    
    func switchRearCamera() throws {
        guard let inputs = captureSession?.inputs as? [AVCaptureInput], let frontCameraInput = self.frontCameraInput, inputs.contains(frontCameraInput), let rearCamera = self.rearCamera else {
            throw CameraControllerError.invalidOperation }
        
        self.rearCameraInput = try AVCaptureDeviceInput(device: rearCamera)
        captureSession?.removeInput(frontCameraInput)
        
        if captureSession!.canAddInput(self.rearCameraInput!) {
            captureSession?.addInput(self.rearCameraInput)
            
            self.currentCameraPosition = .rear
        } else {
            throw CameraControllerError.invalidOperation
        }
    }
}

extension CameraController: AVCapturePhotoCaptureDelegate {
    func captureImage(completion: @escaping (UIImage?, Error?) -> ()) {
        guard let captureSession = self.captureSession, captureSession.isRunning else { completion(nil, CameraControllerError.captureSessionIsMissing); return }
        
        let settings = AVCapturePhotoSettings()
        settings.flashMode = self.flashMode
        
        self.photoOutput?.capturePhoto(with: settings, delegate: self)
        self.photoCaptureCompletionBlock = completion
    }
    
    func capture(_ captureOutput: AVCapturePhotoOutput, didFinishProcessingPhotoSampleBuffer photoSampleBuffer: CMSampleBuffer?, previewPhotoSampleBuffer: CMSampleBuffer?, resolvedSettings: AVCaptureResolvedPhotoSettings, bracketSettings: AVCaptureBracketedStillImageSettings?, error: Error?) {
        if let error = error {
            self.photoCaptureCompletionBlock?(nil, error)
        } else if let buffer = photoSampleBuffer, let data = AVCapturePhotoOutput.jpegPhotoDataRepresentation(forJPEGSampleBuffer: buffer, previewPhotoSampleBuffer: nil), let image = UIImage(data: data) {
            self.photoCaptureCompletionBlock?(image, nil)
        } else {
            self.photoCaptureCompletionBlock?(nil, CameraControllerError.unknown)
        }
    }
}
