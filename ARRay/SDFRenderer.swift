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
   // var capturedImagePipelineState: MTLRenderPipelineState!
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
       // print("Update SDFs");
        let verticies = createRayPlaneVerticies(frame: frame, size: viewportSize, orientation: .landscapeRight)
        
        vertexBuffer?.contents().copyMemory(from: verticies, byteCount: verticies.byteLength)
        
        //updateCapturedImageTextures(frame: frame)
        /*
        if viewportSizeDidChange {
            viewportSizeDidChange = false
            
            updateImagePlane(frame: frame)
        }
         */
    }
    
    
    func drawRectResized(size: CGSize) {
        viewportSize = size
        viewportSizeDidChange = true
    }
    /*
    func updateCapturedImageTextures(frame:ARFrame){
        // Create two textures (Y and CbCr) from the provided frame's captured image
        let pixelBuffer = frame.capturedImage
        
        if (CVPixelBufferGetPlaneCount(pixelBuffer) < 2) {
            return
        }
        
      //  textureY = createTexture(fromPixelBuffer: pixelBuffer, pixelFormat:.r8Unorm, planeIndex:0)
      //  textureCbCr = createTexture(fromPixelBuffer: pixelBuffer, pixelFormat:.rg8Unorm, planeIndex:1)
    }
    */
    /*
    func updateImagePlane(frame: ARFrame) {
        // Update the texture coordinates of our image plane to aspect fill the viewport
        let displayToCameraTransform = frame.displayTransform(for: .landscapeRight, viewportSize: viewportSize).inverted()
        
        let vertexData = rayPlaneVertexBuffer.contents().assumingMemoryBound(to: Float.self)
        
        for index in 0...3 {
            let textureCoordIndex = 4 * index + 2
            let textureCoord = CGPoint(x: CGFloat(kImagePlaneVertexData[textureCoordIndex]), y: CGFloat(kImagePlaneVertexData[textureCoordIndex + 1]))
            let transformedCoord = textureCoord.applying(displayToCameraTransform)
            vertexData[textureCoordIndex] = Float(transformedCoord.x)
            vertexData[textureCoordIndex + 1] = Float(transformedCoord.y)
        }
    }
    */
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
        
        guard   //let textureY = textureY,
               // let textureCbCr = textureCbCr ,
                let pipelineState = pipelineState
                                                    else { return }
        // print("Draw SDFs")
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
       // renderEncoder.drawPrimitives(type: .point , vertexStart: 0, vertexCount: 4)
        
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
        
        let stride =  MemoryLayout<float2>.stride +  MemoryLayout<float3>.stride
        let rpstride = MemoryLayout<RayPlaneVertex>.stride
      
        
        // Buffer Layout
        imagePlaneVertexDescriptor.layouts[0].stride = MemoryLayout<RayPlaneVertex>.stride
        imagePlaneVertexDescriptor.layouts[0].stepRate = 1
        imagePlaneVertexDescriptor.layouts[0].stepFunction = .perVertex
        
        // Create a pipeline state for rendering the captured image
        let capturedImagePipelineStateDescriptor = MTLRenderPipelineDescriptor()
        capturedImagePipelineStateDescriptor.label = "SDFPipeline"
        capturedImagePipelineStateDescriptor.sampleCount = renderDestination.sampleCount
        capturedImagePipelineStateDescriptor.vertexFunction = capturedImageVertexFunction
        capturedImagePipelineStateDescriptor.fragmentFunction = capturedImageFragmentFunction
        capturedImagePipelineStateDescriptor.vertexDescriptor = imagePlaneVertexDescriptor
        capturedImagePipelineStateDescriptor.colorAttachments[0].pixelFormat = renderDestination.colorPixelFormat
        capturedImagePipelineStateDescriptor.depthAttachmentPixelFormat = renderDestination.depthStencilPixelFormat
        capturedImagePipelineStateDescriptor.stencilAttachmentPixelFormat = renderDestination.depthStencilPixelFormat
        
        do {
            try pipelineState = device.makeRenderPipelineState(descriptor: capturedImagePipelineStateDescriptor)
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
