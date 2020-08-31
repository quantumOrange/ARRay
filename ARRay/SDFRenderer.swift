//
//  CapturedImage.swift
//  ARMetalTest
//
//  Created by David Crooks on 12/02/2019.
//  Copyright © 2019 David Crooks. All rights reserved.
//

import Foundation
import Metal

import MetalKit
import ARKit

class SDFRenderer:ARMetalDrawable {
    var pipelineState: MTLRenderPipelineState?
    var renderDestination:RenderDestinationProvider
    
    
    var vertexBuffer: MTLBuffer!
    var depthState: MTLDepthStencilState!
    
    //var textureY: CVMetalTexture?
    //var textureCbCr: CVMetalTexture?
    
    // Captured image texture cache
    var capturedImageTextureCache: CVMetalTextureCache!
    
    // The current viewport size
    var viewportSize: CGSize = CGSize()
    
    // Flag for viewport size changes
    var viewportSizeDidChange: Bool = false
    
    
    func update(frame: ARFrame) {
        let verticies = createRayPlaneVerticies(frame: frame, size: viewportSize, orientation: .landscapeRight)
        vertexBuffer?.contents().copyMemory(from: verticies, byteCount: verticies.byteLength)
    }
    
    
    func drawRectResized(size: CGSize) {
        viewportSize = size
        viewportSizeDidChange = true
    }
  
    func createTexture(fromPixelBuffer pixelBuffer: CVPixelBuffer, pixelFormat: MTLPixelFormat, planeIndex: Int) -> CVMetalTexture? {
        
        let width = CVPixelBufferGetWidthOfPlane(pixelBuffer, planeIndex)
        let height = CVPixelBufferGetHeightOfPlane(pixelBuffer, planeIndex)
        
        var texture: CVMetalTexture? = nil
        let status = CVMetalTextureCacheCreateTextureFromImage(nil, capturedImageTextureCache, pixelBuffer, nil, pixelFormat, width, height, planeIndex, &texture)
        
        if status != kCVReturnSuccess {
            texture = nil
        }
        
        return texture
    }
    
    func draw(renderEncoder: MTLRenderCommandEncoder, sharedUniformBuffer: MTLBuffer, sharedUniformBufferOffset: Int) {
        
        guard  let pipelineState = pipelineState
                                                    else { return }
        // Push a debug group allowing us to identify render commands in the GPU Frame Capture tool
        renderEncoder.pushDebugGroup("Draw SDF ")
        
        // Set render command encoder state
        renderEncoder.setCullMode(.none)
        renderEncoder.setRenderPipelineState(pipelineState)
        renderEncoder.setDepthStencilState(depthState)
        
        // Set mesh's vertex buffers
        renderEncoder.setVertexBuffer(vertexBuffer, offset: 0, index: Int(kBufferIndexMeshPositions.rawValue))
        
        renderEncoder.setFragmentBuffer(sharedUniformBuffer, offset: sharedUniformBufferOffset, index: Int(kBufferIndexSharedUniforms.rawValue))
        
        // Draw each submesh of our mesh
        renderEncoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
        
        renderEncoder.popDebugGroup()
        
    }
    
    init( device:MTLDevice, destination:RenderDestinationProvider ) {
        self.renderDestination = destination
        loadMetal(device:device)
        loadAssets(device:device)
    }
    
    func loadMetal(device:MTLDevice) {
        print("SDF Load Metal")
        // Create a vertex buffer with our image plane vertex data.
        let imagePlaneVertexDataCount = kImagePlaneVertexData.count * MemoryLayout<Float>.size
        vertexBuffer = device.makeBuffer(bytes: kImagePlaneVertexData, length: imagePlaneVertexDataCount, options: [])
        vertexBuffer.label = "ImagePlaneVertexBuffer"
        
        // Load all the shader files with a metal file extension in the project
        let defaultLibrary = device.makeDefaultLibrary()!
        
        let capturedImageVertexFunction = defaultLibrary.makeFunction(name: "sdfVertexShader")!
        let capturedImageFragmentFunction = defaultLibrary.makeFunction(name: "sdfFragmentShader")!
        
        // Create a vertex descriptor for our image plane vertex buffer
        let imagePlaneVertexDescriptor = MTLVertexDescriptor()
        
        // Positions.
        imagePlaneVertexDescriptor.attributes[0].format = .float2
        imagePlaneVertexDescriptor.attributes[0].offset = MemoryLayout<RayPlaneVertex>.offset(of:  \RayPlaneVertex.position) ?? 0
        imagePlaneVertexDescriptor.attributes[0].bufferIndex = Int(kBufferIndexMeshPositions.rawValue)
        
        // Ray Normals.
        imagePlaneVertexDescriptor.attributes[1].format = .float3
        imagePlaneVertexDescriptor.attributes[1].offset = MemoryLayout<RayPlaneVertex>.offset(of: \RayPlaneVertex.rayNormal)!
        imagePlaneVertexDescriptor.attributes[1].bufferIndex = Int(kBufferIndexMeshPositions.rawValue)
      
        // Buffer Layout
        imagePlaneVertexDescriptor.layouts[0].stride = MemoryLayout<RayPlaneVertex>.stride
        imagePlaneVertexDescriptor.layouts[0].stepRate = 1
        imagePlaneVertexDescriptor.layouts[0].stepFunction = .perVertex
        
        // Create a pipeline state for rendering the captured image
        let sdfPipelineStateDescriptor = MTLRenderPipelineDescriptor()
        sdfPipelineStateDescriptor.label = "SDFPipeline"
        sdfPipelineStateDescriptor.sampleCount = renderDestination.sampleCount
        sdfPipelineStateDescriptor.vertexFunction = capturedImageVertexFunction
        sdfPipelineStateDescriptor.fragmentFunction = capturedImageFragmentFunction
        sdfPipelineStateDescriptor.vertexDescriptor = imagePlaneVertexDescriptor
        sdfPipelineStateDescriptor.colorAttachments[0].pixelFormat = renderDestination.colorPixelFormat
        sdfPipelineStateDescriptor.depthAttachmentPixelFormat = renderDestination.depthStencilPixelFormat
        sdfPipelineStateDescriptor.stencilAttachmentPixelFormat = renderDestination.depthStencilPixelFormat
        
        
        if let attachmentDescriptor = sdfPipelineStateDescriptor.colorAttachments[0] {
                   attachmentDescriptor.isBlendingEnabled = true
                   
                   attachmentDescriptor.rgbBlendOperation = MTLBlendOperation.add
                   attachmentDescriptor.sourceRGBBlendFactor = MTLBlendFactor.sourceAlpha
                   attachmentDescriptor.destinationRGBBlendFactor = MTLBlendFactor.oneMinusSourceAlpha
                   
                   attachmentDescriptor.alphaBlendOperation = MTLBlendOperation.add
                   attachmentDescriptor.sourceAlphaBlendFactor = MTLBlendFactor.sourceAlpha
                   attachmentDescriptor.destinationAlphaBlendFactor = MTLBlendFactor.oneMinusSourceAlpha
               }
               
        
        do {
            try pipelineState = device.makeRenderPipelineState(descriptor: sdfPipelineStateDescriptor)
        } catch let error {
            print("Failed to created sdf pipeline state, error \(error)")
        }
        
        let capturedImageDepthStateDescriptor = MTLDepthStencilDescriptor()
        capturedImageDepthStateDescriptor.depthCompareFunction = .always
        capturedImageDepthStateDescriptor.isDepthWriteEnabled = false
        depthState = device.makeDepthStencilState(descriptor: capturedImageDepthStateDescriptor)
        
        // Create captured image texture cache
        var textureCache: CVMetalTextureCache?
        CVMetalTextureCacheCreate(nil, nil, device, nil, &textureCache)
        capturedImageTextureCache = textureCache
    }
    
    func loadAssets(device:MTLDevice) {
        
    }
    
}
