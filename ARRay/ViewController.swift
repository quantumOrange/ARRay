//
//  ViewController.swift
//  ARMetalTest
//
//  Created by David Crooks on 07/02/2019.
//  Copyright © 2019 David Crooks. All rights reserved.
//

import UIKit
import Metal
import MetalKit
import ARKit

extension MTKView : RenderDestinationProvider {
    
}

struct SDFObject {
    var origin:SIMD3<Float>
    var transform: simd_float4x4
    var radius:Float
}

class ViewController: UIViewController, MTKViewDelegate, ARSessionDelegate {
    
    
    struct ManualProbe {
        // An environment probe for shading the virtual object.
        let objectProbeAnchorIdentifyer:String = "objectProbe"
        let sceneProbeAnchorIdentifyer:String = "sceneProbe"
        
        var objectProbeAnchor: AREnvironmentProbeAnchor?
        // A fallback environment probe encompassing the whole scene.
        var sceneProbeAnchor: AREnvironmentProbeAnchor?
        // Indicates whether manually placed probes need updating.
        var requiresRefresh: Bool = true
        // Tracks timing of manual probe updates to prevent updating too frequently.
        var lastUpdateTime: TimeInterval = 0
    }
    
    /// The virtual object that the user interacts with in the scene.
    var virtualObject: SDFObject?
    
    
    /// Object to manage the manual environment probe anchor and its state
    var manualProbe: ManualProbe = ManualProbe()
    var session: ARSession!
    var renderer: Renderer!
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        // Set the view's delegate
        session = ARSession()
        session.delegate = self
        
        
        
        
        
        // Set the view to use the default device
        if let view = self.view as? MTKView {
            view.device = MTLCreateSystemDefaultDevice()
            view.backgroundColor = UIColor.clear
            view.delegate = self
            
            guard view.device != nil else {
                print("Metal is not supported on this device")
                return
            }
            
            // Configure the renderer to draw to the view
            renderer = Renderer(session: session, metalDevice: view.device!, renderDestination: view)
            //view.drawableSize
            renderer.drawRectResized(size: view.bounds.size)
        }
        
        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(ViewController.handleTap(gesture:)))
        view.addGestureRecognizer(tapGesture)
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        
        // Create a session configuration
        let configuration = ARWorldTrackingConfiguration()
        
        configuration.environmentTexturing = .manual
        
        // Run the view's session
        session.run(configuration)
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        
        // Pause the view's session
        session.pause()
    }
    
    @objc
    func handleTap(gesture: UITapGestureRecognizer) {
        // Create anchor using the camera's current position
        if let currentFrame = session.currentFrame {
            
            // Create a transform with a translation of 0.2 meters in front of the camera
            var translation = matrix_identity_float4x4
            translation.columns.3.z = -0.75
            let transform = simd_mul(currentFrame.camera.transform, translation)
            
            // Add a new anchor to the session
            let anchor = ARAnchor(transform: transform)
            
            session.add(anchor: anchor)
            let origin = SIMD4<Float>(0,0,0,1)
            
            if virtualObject == nil {
                let p = simd_mul(transform,origin)
                renderer.sharedUniforms.objectPosition = SIMD3<Float>(p.x,p.y,p.z)
                virtualObject = SDFObject(origin: SIMD3<Float>(p.x,p.y,p.z), transform: transform, radius: 0.2)
                manualProbe.requiresRefresh = true
            }
            print("Added a virtual object");
            /*
            let screenPoint = gesture.location(in: view)
            
          
        
            let xAxis = simd_float3(x: 1,
                                    y: 0,
                                    z: 0)
            
            
            let rotation = float4x4(simd_quatf(angle: 0.5 * .pi ,
                                               axis: xAxis))
            
            let plane = simd_mul(transform,rotation)
            
            if let p = currentFrame.camera.unprojectPoint(screenPoint, ontoPlane: plane, orientation:interfaceOrientation, viewportSize: view.bounds.size) {
                renderer.points.add(point:p, color:SIMD4<Float>(1.0,0.0,0.0,1.0))
                renderer.sharedUniforms.objectPosition = p
                print("p:\(p)")
            }
            
            let anchor = ARAnchor(transform: transform)
            session.add(anchor: anchor)
            */
        }
    }
    
    @IBAction func selectMode(_ sender: UISegmentedControl) {
        if let mode = DisplayMode(rawValue:sender.selectedSegmentIndex) {
            renderer.displayMode = mode
        }
        //switsender.selectedSegmentIndex
    }
    
    // MARK: - MTKViewDelegate

    // Called whenever view changes orientation or layout is changed
    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        renderer.drawRectResized(size: size)
    }
    
    // Called whenever the view needs to render
    func draw(in view: MTKView) {
        
        let time = CACurrentMediaTime()
        updateEnvironmentProbe(atTime: time)
        
        renderer.update()
    }
    
    // MARK: - Environment Texturing
       
    /// - Tag: ManualProbePlacement
    func updateEnvironmentProbe(atTime time: TimeInterval) {
        // Update the probe only if the object has been moved or scaled,
        // only when manually placed, not too often.
       
        guard let object = virtualObject,
           time - manualProbe.lastUpdateTime >= 1.0,
           manualProbe.requiresRefresh
           else { return }
        print("Update probe at Time \(time)")
        // Remove existing probe anchor, if any.
        if let probeAnchor = manualProbe.objectProbeAnchor {
           session.remove(anchor: probeAnchor)
           manualProbe.objectProbeAnchor = nil
        }

        // Make sure the probe encompasses the object and provides some surrounding area to appear in reflections.
        let e = 5*object.radius;
        let extent = SIMD3<Float>(e,e,e)

        // Create the new environment probe anchor and add it to the session.
        let probeAnchor = AREnvironmentProbeAnchor(name:manualProbe.objectProbeAnchorIdentifyer, transform: object.transform, extent: extent)
        session.add(anchor: probeAnchor)

        // Remember state to prevent updating the environment probe too often.
        manualProbe.objectProbeAnchor = probeAnchor
        manualProbe.lastUpdateTime = CACurrentMediaTime()
        manualProbe.requiresRefresh = false

    }

    /// - Tag: FallbackEnvironmentProbe
    func updateSceneEnvironmentProbe(for frame: ARFrame) {
        if manualProbe.sceneProbeAnchor != nil
            { return }

        // Create an environment probe anchor with room-sized extent to act as fallback when the probe anchor of
        // an object is removed and added during translation and scaling
        let probeAnchor = AREnvironmentProbeAnchor(name: manualProbe.sceneProbeAnchorIdentifyer, transform: matrix_identity_float4x4, extent: SIMD3<Float>(repeating: 5))
        session.add(anchor: probeAnchor)
        self.manualProbe.sceneProbeAnchor = probeAnchor
    }

    
    // MARK: - ARSessionDelegate
    
    func session(_ session: ARSession, didFailWithError error: Error) {
        // Present an error message to the user
        
    }
    
    func session(_ session: ARSession, didUpdate frame: ARFrame) {
        updateSceneEnvironmentProbe(for: frame)
        
    }
    
    func session(_ session: ARSession, didUpdate anchors: [ARAnchor]) {
           print("--------")
           let probes =  anchors
                           .compactMap { $0 as? AREnvironmentProbeAnchor }
           
           probes.forEach{
               if($0.environmentTexture == nil){
                   print("Envirment Texture  NOT Availablefor probe \(String(describing: $0.name))")
                    
               }
               else {
                if($0.name == manualProbe.objectProbeAnchorIdentifyer) {
                    renderer.sdf.objectEnviromentTexture = $0.environmentTexture
                }
                else {
                    assert($0.name == manualProbe.sceneProbeAnchorIdentifyer)
                    renderer.sdf.sceneEnviromentTexture = $0.environmentTexture
                }
                   print("Envirment Texture Available for probe \(String(describing: $0.name))")
               }
           }
           
       }

    
    func sessionWasInterrupted(_ session: ARSession) {
        // Inform the user that the session has been interrupted, for example, by presenting an overlay
        
    }
    
    func sessionInterruptionEnded(_ session: ARSession) {
        // Reset tracking and/or remove existing anchors if consistent tracking is required
        
    }
}
