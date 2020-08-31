//
//  RayNormals.swift
//  ARRay
//
//  Created by David Crooks on 15/02/2019.
//  Copyright © 2019 David Crooks. All rights reserved.
//

import Foundation
import ARKit
import CoreGraphics

struct RayPlaneVertex {
    let position:float2
    let rayNormal:float3
}

/*
let kImagePlaneVertexData: [Float] = [
    -1.0, -1.0,  0.0, 1.0,
    1.0, -1.0,  1.0, 1.0,
    -1.0,  1.0,  0.0, 0.0,
    1.0,  1.0,  1.0, 0.0,
]
*/
    
func createRayPlaneVerticies(frame:ARFrame, size:CGSize, orientation:UIInterfaceOrientation) -> [RayPlaneVertex] {
    
    let origin = float4(0,0,0,1)
    let cameraPoition4d = simd_mul(frame.camera.transform, origin)
    let cameraPoition = float3(cameraPoition4d.x,cameraPoition4d.y,cameraPoition4d.z)
    
    var translation = matrix_identity_float4x4
    translation.columns.3.z = -0.2
    let transform = simd_mul(frame.camera.transform, translation)
    
    let xAxis = simd_float3(x: 1,
                            y: 0,
                            z: 0)
    
    let rotation = float4x4(simd_quatf(angle: 0.5 * .pi ,
                                       axis: xAxis))
    
    let plane = simd_mul(transform,rotation)
    
    
    let positions = [
                        float2(x: -1.0, y: -1.0),
                        float2(x: 1.0, y: -1.0),
                        float2(x: -1.0, y: 1.0),
                        float2(x: 1.0, y: 1.0)
                    ]
                     
    
    let screenPoints = [
                            CGPoint(x: 0.0, y:  size.height),
                            CGPoint(x: size.width, y:  size.height),
                            CGPoint(x: 0.0, y:  0.0),
                            CGPoint(x: size.width, y:  0.0)
                        ]
    
    let spacePoints = screenPoints.compactMap {
        return frame.camera.unprojectPoint($0, ontoPlane: plane, orientation:orientation, viewportSize: size)
    }
    
    let rayNormals = spacePoints.map {
       
        return simd_normalize(cameraPoition - $0)
    }
    
    return zip( positions, rayNormals ).map(RayPlaneVertex.init)
}
    

    

