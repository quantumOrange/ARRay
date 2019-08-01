//
//  cubeAnchorsRenderer.swift
//  ARMetalTest
//
//  Created by David Crooks on 11/02/2019.
//  Copyright © 2019 David Crooks. All rights reserved.
//

import Foundation
import ARKit
import MetalKit

class Cubes: ARMetalDrawable {
    var pipelineState: MTLRenderPipelineState?
    var anchorUniformBuffer: MTLBuffer!
    // var sharedUniformBuffer: MTLBuffer!
    //var anchorPipelineState: MTLRenderPipelineState!
    var depthState: MTLDepthStencilState!
    
    var renderDestination:RenderDestinationProvider
    
    // Addresses to write anchor uniforms to each frame
    var anchorUniformBufferAddress: UnsafeMutableRawPointer!
    
    // Offset within _sharedUniformBuffer to set for the current frame
    var sharedUniformBufferOffset: Int = 0
    
    // Offset within _anchorUniformBuffer to set for the current frame
    var anchorUniformBufferOffset: Int = 0
    
    // Addresses to write shared uniforms to each frame
    var sharedUniformBufferAddress: UnsafeMutableRawPointer!
    
    // MetalKit mesh containing vertex data and index buffer for our anchor geometry
    var cubeMesh: MTKMesh!
    
    var geometryVertexDescriptor:MTLVertexDescriptor!
    
    // The number of anchor instances to render
    var instanceCount: Int = 0
    
    init( device:MTLDevice, destination:RenderDestinationProvider ) {
        self.renderDestination = destination
        loadMetal(device:device)
        loadAssets(device:device)
    }
    
    func loadMetal(device:MTLDevice) {
        
        let anchorUniformBufferSize = kAlignedInstanceUniformsSize * kMaxBuffersInFlight
        anchorUniformBuffer = device.makeBuffer(length: anchorUniformBufferSize, options: .storageModeShared)
        
        anchorUniformBuffer.label = "AnchorUniformBuffer"
        
        let defaultLibrary = device.makeDefaultLibrary()!
        let anchorGeometryVertexFunction = defaultLibrary.makeFunction(name: "anchorGeometryVertexTransform")!
        let anchorGeometryFragmentFunction = defaultLibrary.makeFunction(name: "anchorGeometryFragmentLighting")!
        
        // Create a vertex descriptor for our Metal pipeline. Specifies the layout of vertices the
        //   pipeline should expect. The layout below keeps attributes used to calculate vertex shader
        //   output position separate (world position, skinning, tweening weights) separate from other
        //   attributes (texture coordinates, normals).  This generally maximizes pipeline efficiency
        geometryVertexDescriptor = MTLVertexDescriptor()
        
        // Positions.
        geometryVertexDescriptor.attributes[0].format = .float3
        geometryVertexDescriptor.attributes[0].offset = 0
        geometryVertexDescriptor.attributes[0].bufferIndex = Int(kBufferIndexMeshPositions.rawValue)
        
        // Texture coordinates.
        geometryVertexDescriptor.attributes[1].format = .float2
        geometryVertexDescriptor.attributes[1].offset = 0
        geometryVertexDescriptor.attributes[1].bufferIndex = Int(kBufferIndexMeshGenerics.rawValue)
        
        // Normals.
        geometryVertexDescriptor.attributes[2].format = .half3
        geometryVertexDescriptor.attributes[2].offset = 8
        geometryVertexDescriptor.attributes[2].bufferIndex = Int(kBufferIndexMeshGenerics.rawValue)
        
        // Position Buffer Layout
        geometryVertexDescriptor.layouts[0].stride = 12
        geometryVertexDescriptor.layouts[0].stepRate = 1
        geometryVertexDescriptor.layouts[0].stepFunction = .perVertex
        
        // Generic Attribute Buffer Layout
        geometryVertexDescriptor.layouts[1].stride = 16
        geometryVertexDescriptor.layouts[1].stepRate = 1
        geometryVertexDescriptor.layouts[1].stepFunction = .perVertex
        
        // Create a reusable pipeline state for rendering anchor geometry
        let anchorPipelineStateDescriptor = MTLRenderPipelineDescriptor()
        anchorPipelineStateDescriptor.label = "MyAnchorPipeline"
        anchorPipelineStateDescriptor.sampleCount = renderDestination.sampleCount
        anchorPipelineStateDescriptor.vertexFunction = anchorGeometryVertexFunction
        anchorPipelineStateDescriptor.fragmentFunction = anchorGeometryFragmentFunction
        anchorPipelineStateDescriptor.vertexDescriptor = geometryVertexDescriptor
        anchorPipelineStateDescriptor.colorAttachments[0].pixelFormat = renderDestination.colorPixelFormat
        anchorPipelineStateDescriptor.depthAttachmentPixelFormat = renderDestination.depthStencilPixelFormat
        anchorPipelineStateDescriptor.stencilAttachmentPixelFormat = renderDestination.depthStencilPixelFormat
        
        do {
            try pipelineState = device.makeRenderPipelineState(descriptor: anchorPipelineStateDescriptor)
        } catch let error {
            print("Failed to created anchor geometry pipeline state, error \(error)")
        }
        
        let anchorDepthStateDescriptor = MTLDepthStencilDescriptor()
        anchorDepthStateDescriptor.depthCompareFunction = .less
        anchorDepthStateDescriptor.isDepthWriteEnabled = true
        depthState = device.makeDepthStencilState(descriptor: anchorDepthStateDescriptor)
    }
    
    func loadAssets(device:MTLDevice) {
        // Create and load our assets into Metal objects including meshes and textures
        
        // Create a MetalKit mesh buffer allocator so that ModelIO will load mesh data directly into
        //   Metal buffers accessible by the GPU
        let metalAllocator = MTKMeshBufferAllocator(device: device)
        
        // Creata a Model IO vertexDescriptor so that we format/layout our model IO mesh vertices to
        //   fit our Metal render pipeline's vertex descriptor layout
        let vertexDescriptor = MTKModelIOVertexDescriptorFromMetal(geometryVertexDescriptor)
        
        // Indicate how each Metal vertex descriptor attribute maps to each ModelIO attribute
        (vertexDescriptor.attributes[Int(kVertexAttributePosition.rawValue)] as! MDLVertexAttribute).name = MDLVertexAttributePosition
        (vertexDescriptor.attributes[Int(kVertexAttributeTexcoord.rawValue)] as! MDLVertexAttribute).name = MDLVertexAttributeTextureCoordinate
        (vertexDescriptor.attributes[Int(kVertexAttributeNormal.rawValue)] as! MDLVertexAttribute).name   = MDLVertexAttributeNormal
        
        // Use ModelIO to create a box mesh as our object
        //let mesh = MDLMesh(boxWithExtent: vector3(0.075, 0.075, 0.075), segments: vector3(1, 1, 1), inwardNormals: false, geometryType: .triangles, allocator: metalAllocator)
        
        
        let mesh = MDLMesh(icosahedronWithExtent: vector3(0.05, 0.05, 0.05), inwardNormals: true, geometryType: .triangles, allocator: metalAllocator)
        // Perform the format/relayout of mesh vertices by setting the new vertex descriptor in our
        //   Model IO mesh
        mesh.vertexDescriptor = vertexDescriptor
        
        // Create a MetalKit mesh (and submeshes) backed by Metal buffers
        do {
            try cubeMesh = MTKMesh(mesh: mesh, device: device)
        } catch let error {
            print("Error creating MetalKit mesh, error \(error)")
        }
    }
    
    
    func updateBufferStates() {
        
      //  sharedUniformBufferAddress = sharedUniformBuffer.contents().advanced(by: sharedUniformBufferOffset)
        anchorUniformBufferAddress = anchorUniformBuffer.contents().advanced(by: anchorUniformBufferOffset)
        
    }
    
    
    func update(frame: ARFrame){
        updateBufferStates()
        // Update the anchor uniform buffer with transforms of the current frame's anchors
        instanceCount = min(frame.anchors.count, kMaxAnchorInstanceCount)
        
        var anchorOffset: Int = 0
        if instanceCount == kMaxAnchorInstanceCount {
            anchorOffset = max(frame.anchors.count - kMaxAnchorInstanceCount, 0)
        }
        
        for index in 0..<instanceCount {
            let anchor = frame.anchors[index + anchorOffset]
            
            // Flip Z axis to convert geometry from right handed to left handed
            var coordinateSpaceTransform = matrix_identity_float4x4
            coordinateSpaceTransform.columns.2.z = -1.0
            
            let modelMatrix = simd_mul(anchor.transform, coordinateSpaceTransform)
            
            let anchorUniforms = anchorUniformBufferAddress.assumingMemoryBound(to: InstanceUniforms.self).advanced(by: index)
            anchorUniforms.pointee.modelMatrix = modelMatrix
        }
    }
    
    func draw(renderEncoder: MTLRenderCommandEncoder,sharedUniformBuffer: MTLBuffer,sharedUniformBufferOffset:Int ) {
        guard instanceCount > 0,
            let pipelineState = pipelineState
        else {
            return
        }
        
        // Push a debug group allowing us to identify render commands in the GPU Frame Capture tool
        renderEncoder.pushDebugGroup("DrawAnchors")
        
        // Set render command encoder state
        renderEncoder.setCullMode(.back)
        renderEncoder.setRenderPipelineState(pipelineState)
        renderEncoder.setDepthStencilState(depthState)
        
        // Set any buffers fed into our render pipeline
        renderEncoder.setVertexBuffer(anchorUniformBuffer, offset: anchorUniformBufferOffset, index: Int(kBufferIndexInstanceUniforms.rawValue))
        renderEncoder.setVertexBuffer(sharedUniformBuffer, offset: sharedUniformBufferOffset, index: Int(kBufferIndexSharedUniforms.rawValue))
        renderEncoder.setFragmentBuffer(sharedUniformBuffer, offset: sharedUniformBufferOffset, index: Int(kBufferIndexSharedUniforms.rawValue))
        
        // Set mesh's vertex buffers
        for bufferIndex in 0..<cubeMesh.vertexBuffers.count {
            let vertexBuffer = cubeMesh.vertexBuffers[bufferIndex]
            renderEncoder.setVertexBuffer(vertexBuffer.buffer, offset: vertexBuffer.offset, index:bufferIndex)
        }
        
        // Draw each submesh of our mesh
        for submesh in cubeMesh.submeshes {
            renderEncoder.drawIndexedPrimitives(type: submesh.primitiveType, indexCount: submesh.indexCount, indexType: submesh.indexType, indexBuffer: submesh.indexBuffer.buffer, indexBufferOffset: submesh.indexBuffer.offset, instanceCount: instanceCount)
        }
        
        renderEncoder.popDebugGroup()
    }
}
