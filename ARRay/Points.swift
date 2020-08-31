//
//  Points.swift
//  ARMetalTest
//
//  Created by David Crooks on 12/02/2019.
//  Copyright © 2019 David Crooks. All rights reserved.
//

import Foundation


import ARKit
import MetalKit

struct PointVertex {
    let position:float3
    let color:float4
}

class Points: ARMetalDrawable {
    var vertices:[PointVertex] = []
    
    var depthState: MTLDepthStencilState!
    
    func add(point:float3, color:float4) {
        vertices.append(PointVertex(position:point,color:color))
        buildBuffers(device:self.device)
    }
    
    
    func updateBuffer(frame:ARFrame){
        let v = simd_mul(frame.camera.transform,float4(0,0,0,1))
        
        func dist(_ p:float3) -> Float {
            return simd_distance(p,float3(v.x,v.y,v.z))
        }
        
        func furthestFromCamera(_ p:PointVertex,_ q:PointVertex) -> Bool {
            return dist(p.position) > dist(q.position)
        }
        
        vertices.sort(by: furthestFromCamera)
        
        vertexBuffer?.contents().copyMemory(from: vertices, byteCount: vertices.byteLength)
    }
    
    var pipelineState: MTLRenderPipelineState?
   
    var vertexBuffer: MTLBuffer?
    //var indexBuffer: MTLBuffer?
    
    private func buildBuffers(device: MTLDevice) {
        
        if vertices.count > 0 {
            vertexBuffer = device.makeBuffer(bytes: vertices,
                                         length: vertices.byteLength,
                                         options: [])
        }

    }
    
    var renderDestination:RenderDestinationProvider
    
    var vertexDescriptor:MTLVertexDescriptor!
    var device:MTLDevice!
   
    init( device:MTLDevice, destination:RenderDestinationProvider ) {
        self.renderDestination = destination
        self.device = device
        loadMetal(device:device)// loadAssets(device:device)
    }
    
    func loadMetal(device:MTLDevice) {
        
        //let anchorUniformBufferSize = kAlignedInstanceUniformsSize * kMaxBuffersInFlight
       
        buildBuffers(device: device)
        
        let defaultLibrary = device.makeDefaultLibrary()!
        let vertexFunction = defaultLibrary.makeFunction(name: "pointVertex")!
        let fragmentFunction = defaultLibrary.makeFunction(name: "pointFragment")!
        
        // Create a vertex descriptor for our Metal pipeline. Specifies the layout of vertices the
        //   pipeline should expect. The layout below keeps attributes used to calculate vertex shader
        //   output position separate (world position, skinning, tweening weights) separate from other
        //   attributes (texture coordinates, normals).  This generally maximizes pipeline efficiency
        vertexDescriptor = MTLVertexDescriptor()
        
        vertexDescriptor.attributes[0].format = .float3
        vertexDescriptor.attributes[0].offset = 0
        vertexDescriptor.attributes[0].bufferIndex = 0
        
        
        vertexDescriptor.attributes[1].format = .float4
        vertexDescriptor.attributes[1].offset = MemoryLayout<float3>.stride
        vertexDescriptor.attributes[1].bufferIndex = 0
        
        /*
        vertexDescriptor.attributes[2].format = .float2
        vertexDescriptor.attributes[2].offset = MemoryLayout<float3>.stride + MemoryLayout<float4>.stride
        vertexDescriptor.attributes[2].bufferIndex = 0
        */
        
        vertexDescriptor.layouts[0].stride = MemoryLayout<PointVertex>.stride
 
        // Create a reusable pipeline state for rendering anchor geometry
        let pipelineDescriptor = MTLRenderPipelineDescriptor()
        pipelineDescriptor.vertexFunction = vertexFunction
        pipelineDescriptor.fragmentFunction = fragmentFunction
       // pipelineDescriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
        
        pipelineDescriptor.label = "MyPointsPipeline"
        pipelineDescriptor.sampleCount = renderDestination.sampleCount
        
        pipelineDescriptor.colorAttachments[0].pixelFormat = renderDestination.colorPixelFormat
        pipelineDescriptor.depthAttachmentPixelFormat = renderDestination.depthStencilPixelFormat
        pipelineDescriptor.stencilAttachmentPixelFormat = renderDestination.depthStencilPixelFormat
        
        pipelineDescriptor.vertexDescriptor = vertexDescriptor
        
        if let attachmentDescriptor = pipelineDescriptor.colorAttachments[0] {
            attachmentDescriptor.isBlendingEnabled = true
            
            attachmentDescriptor.rgbBlendOperation = MTLBlendOperation.add
            attachmentDescriptor.sourceRGBBlendFactor = MTLBlendFactor.sourceAlpha
            attachmentDescriptor.destinationRGBBlendFactor = MTLBlendFactor.oneMinusSourceAlpha
            
            attachmentDescriptor.alphaBlendOperation = MTLBlendOperation.add
            attachmentDescriptor.sourceAlphaBlendFactor = MTLBlendFactor.sourceAlpha
            attachmentDescriptor.destinationAlphaBlendFactor = MTLBlendFactor.oneMinusSourceAlpha
        }
        
        let depthStencilDescriptor = MTLDepthStencilDescriptor()
        depthStencilDescriptor.depthCompareFunction = .lessEqual
        depthStencilDescriptor.isDepthWriteEnabled = true
        
        depthState = device.makeDepthStencilState(descriptor:depthStencilDescriptor)
        
        do {
            try pipelineState = device.makeRenderPipelineState(descriptor: pipelineDescriptor)
        } catch let error {
            print("Failed to created anchor geometry pipeline state, error \(error)")
        }
        
    }
    
    
    func update(frame: ARFrame){
        //buildBuffers(device: devi)
        updateBuffer(frame: frame)
    }
    
    func draw(renderEncoder: MTLRenderCommandEncoder,sharedUniformBuffer: MTLBuffer,sharedUniformBufferOffset:Int ) {
        
        guard   let pipelineState = pipelineState,
                let vertexBuffer = vertexBuffer
                                            else { return }
        
        // Push a debug group allowing us to identify render commands in the GPU Frame Capture tool
        renderEncoder.pushDebugGroup("DrawPionts")
        
        //renderEncoder.setCullMode(.front)
        renderEncoder.setRenderPipelineState(pipelineState)
        //renderEncoder.setDepthStencilState(depthState)
        
        renderEncoder.setVertexBuffer(vertexBuffer,
                                      offset: 0, index: Int(kBufferIndexMeshPositions.rawValue))
        
        renderEncoder.setVertexBuffer(sharedUniformBuffer, offset: sharedUniformBufferOffset, index: Int(kBufferIndexSharedUniforms.rawValue))
        
        renderEncoder.setFragmentBuffer(sharedUniformBuffer, offset: sharedUniformBufferOffset, index: Int(kBufferIndexSharedUniforms.rawValue))
       
        
        renderEncoder.drawPrimitives(type: .point, vertexStart: 0, vertexCount: vertices.count)
        renderEncoder.popDebugGroup()
    }
}
