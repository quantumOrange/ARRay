//
//  Renderer.swift
//  ARMetalTest
//
//  Created by David Crooks on 07/02/2019.
//  Copyright © 2019 David Crooks. All rights reserved.
//

import Foundation
import Metal
import MetalKit
import ARKit

enum DisplayMode:Int {
    case cubes
    case points
    case both
}

protocol RenderDestinationProvider {
    var currentRenderPassDescriptor: MTLRenderPassDescriptor? { get }
    var currentDrawable: CAMetalDrawable? { get }
    var colorPixelFormat: MTLPixelFormat { get set }
    var depthStencilPixelFormat: MTLPixelFormat { get set }
    var sampleCount: Int { get set }
    var drawableSize:CGSize { get }
}

// The max number of command buffers in flight
let kMaxBuffersInFlight: Int = 3

// The max number anchors our uniform buffer will hold
let kMaxAnchorInstanceCount: Int = 64

// The 16 byte aligned size of our uniform structures
let kAlignedSharedUniformsSize: Int = (MemoryLayout<SharedUniforms>.size & ~0xFF) + 0x100
let kAlignedInstanceUniformsSize: Int = ((MemoryLayout<InstanceUniforms>.size * kMaxAnchorInstanceCount) & ~0xFF) + 0x100


class Renderer {
    var displayMode:DisplayMode = .cubes
    
    let session: ARSession
    let device: MTLDevice
    let inFlightSemaphore = DispatchSemaphore(value: kMaxBuffersInFlight)
    var renderDestination: RenderDestinationProvider
    
    // Metal objects
    var commandQueue: MTLCommandQueue!
    var sharedUniformBuffer: MTLBuffer!
    
    
    
    // Metal vertex descriptor specifying how vertices will by laid out for input into our
    //   anchor geometry render pipeline and how we'll layout our Model IO verticies
    

    
    // Used to determine _uniformBufferStride each frame.
    //   This is the current frame number modulo kMaxBuffersInFlight
    var uniformBufferIndex: Int = 0
    
    // Offset within _sharedUniformBuffer to set for the current frame
     var sharedUniformBufferOffset: Int = 0
    
    // Offset within _anchorUniformBuffer to set for the current frame
  //  var anchorUniformBufferOffset: Int = 0
    
    // Addresses to write shared uniforms to each frame
     var sharedUniformBufferAddress: UnsafeMutableRawPointer!
    
    let points:Points
    let cubes:Cubes
    let capturedImage:CapturedImage
    let sdf:SDFRenderer
    let drawables:[ARMetalDrawable]
    
    init(session: ARSession, metalDevice device: MTLDevice, renderDestination: RenderDestinationProvider) {
        self.session = session
        self.device = device
        // Set the default formats needed to render
        
        self.renderDestination = renderDestination
        self.renderDestination.depthStencilPixelFormat = .depth32Float_stencil8
        self.renderDestination.colorPixelFormat = .bgra8Unorm
        self.renderDestination.sampleCount = 1
        
        self.cubes = Cubes(device:device, destination:renderDestination)
        self.capturedImage = CapturedImage(device:device, destination:renderDestination)
        self.sdf = SDFRenderer(device: device, destination: renderDestination)
        self.points = Points(device:device, destination:renderDestination)
        
        self.drawables = [ capturedImage, cubes, points];
        
        loadMetal()
        
    }
    
    func update() {
        
        // Wait to ensure only kMaxBuffersInFlight are getting proccessed by any stage in the Metal
        //   pipeline (App, Metal, Drivers, GPU, etc)
        let _ = inFlightSemaphore.wait(timeout: DispatchTime.distantFuture)
        
        // Create a new command buffer for each renderpass to the current drawable
        if let commandBuffer = commandQueue.makeCommandBuffer() {
            commandBuffer.label = "MyCommand"
            
            // Add completion hander which signal _inFlightSemaphore when Metal and the GPU has fully
            //   finished proccssing the commands we're encoding this frame.  This indicates when the
            //   dynamic buffers, that we're writing to this frame, will no longer be needed by Metal
            //   and the GPU.
            // Retain our CVMetalTextures for the duration of the rendering cycle. The MTLTextures
            //   we use from the CVMetalTextures are not valid unless their parent CVMetalTextures
            //   are retained. Since we may release our CVMetalTexture ivars during the rendering
            //   cycle, we must retain them separately here.
            var textures = [capturedImage.textureY, capturedImage.textureCbCr]
            commandBuffer.addCompletedHandler{ [weak self] commandBuffer in
                if let strongSelf = self {
                    strongSelf.inFlightSemaphore.signal()
                }
                textures.removeAll()
            }
            
            updateBufferStates()
            updateGameState()
            
            draw(commandBuffer:commandBuffer)
        }
    }
    
    
    func draw(commandBuffer:MTLCommandBuffer){
        if let renderPassDescriptor = renderDestination.currentRenderPassDescriptor, let currentDrawable = renderDestination.currentDrawable, let renderEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor) {
            
            renderEncoder.label = "MyRenderEncoder"
            
            /*
            drawables.forEach{
                $0.draw(renderEncoder: renderEncoder,sharedUniformBuffer:sharedUniformBuffer,sharedUniformBufferOffset: sharedUniformBufferOffset)
            }
            */
            
            capturedImage.draw(renderEncoder: renderEncoder,sharedUniformBuffer:sharedUniformBuffer,sharedUniformBufferOffset: sharedUniformBufferOffset)
            
            
            sdf.draw(renderEncoder: renderEncoder,sharedUniformBuffer:sharedUniformBuffer,sharedUniformBufferOffset: sharedUniformBufferOffset)
            /*
            switch displayMode {
            case .cubes:
                cubes.draw(renderEncoder: renderEncoder,sharedUniformBuffer:sharedUniformBuffer,sharedUniformBufferOffset: sharedUniformBufferOffset)
            case .points:
                points.draw(renderEncoder: renderEncoder,sharedUniformBuffer:sharedUniformBuffer,sharedUniformBufferOffset: sharedUniformBufferOffset)
            case .both:
                cubes.draw(renderEncoder: renderEncoder,sharedUniformBuffer:sharedUniformBuffer,sharedUniformBufferOffset: sharedUniformBufferOffset)
                points.draw(renderEncoder: renderEncoder,sharedUniformBuffer:sharedUniformBuffer,sharedUniformBufferOffset: sharedUniformBufferOffset)
            }
            
            */
            
            // We're done encoding commands
            renderEncoder.endEncoding()
            
            // Schedule a present once the framebuffer is complete using the current drawable
            commandBuffer.present(currentDrawable)
        }
        
        // Finalize rendering here & push the command buffer to the GPU
        commandBuffer.commit()
    }
    
    // MARK: - Private
    
    func loadMetal() {
        // Create and load our basic Metal state objects
        
        // Calculate our uniform buffer sizes. We allocate kMaxBuffersInFlight instances for uniform
        //   storage in a single buffer. This allows us to update uniforms in a ring (i.e. triple
        //   buffer the uniforms) so that the GPU reads from one slot in the ring wil the CPU writes
        //   to another. Anchor uniforms should be specified with a max instance count for instancing.
        //   Also uniform storage must be aligned (to 256 bytes) to meet the requirements to be an
        //   argument in the constant address space of our shading functions.
        let sharedUniformBufferSize = kAlignedSharedUniformsSize * kMaxBuffersInFlight
        
        // Create and allocate our uniform buffer objects. Indicate shared storage so that both the
        //   CPU can access the buffer
        sharedUniformBuffer = device.makeBuffer(length: sharedUniformBufferSize, options: .storageModeShared)
        sharedUniformBuffer.label = "SharedUniformBuffer"
        
        // Create the command queue
        commandQueue = device.makeCommandQueue()
    }
    
    
    func updateBufferStates() {
        // Update the location(s) to which we'll write to in our dynamically changing Metal buffers for
        //   the current frame (i.e. update our slot in the ring buffer used for the current frame)
        
        uniformBufferIndex = (uniformBufferIndex + 1) % kMaxBuffersInFlight
        
        sharedUniformBufferOffset = kAlignedSharedUniformsSize * uniformBufferIndex
        //anchorUniformBufferOffset = kAlignedInstanceUniformsSize * uniformBufferIndex
        
        sharedUniformBufferAddress = sharedUniformBuffer.contents().advanced(by: sharedUniformBufferOffset)
       // anchorUniformBufferAddress = anchorUniformBuffer.contents().advanced(by: anchorUniformBufferOffset)
    }
    
    func updateGameState() {
        // Update any game state
        
        guard let currentFrame = session.currentFrame else {
            return
        }
        
        updateSharedUniforms(frame: currentFrame)
        
        
        
        sdf.update(frame: currentFrame)
        
        drawables.forEach{
            $0.update(frame: currentFrame)
        }
        
    }
    
    func drawRectResized(size: CGSize) {
        viewportSize = size
        capturedImage.drawRectResized(size: size)
        sdf.drawRectResized(size: size)
       // viewportSizeDidChange = true
    }
    
    // The current viewport size
    var viewportSize: CGSize = CGSize()
    
    // Flag for viewport size changes
    //var viewportSizeDidChange: Bool = false
    
    
    
    func updateSharedUniforms(frame: ARFrame) {
        // Update the shared uniforms of the frame
        
        let uniforms = sharedUniformBufferAddress.assumingMemoryBound(to: SharedUniforms.self)
        
        uniforms.pointee.viewMatrix = frame.camera.viewMatrix(for: .landscapeRight)
        uniforms.pointee.projectionMatrix = frame.camera.projectionMatrix(for: .landscapeRight, viewportSize: viewportSize, zNear: 0.001, zFar: 1000)

        // Set up lighting for the scene using the ambient intensity if provided
        var ambientIntensity: Float = 1.0
        
        if let lightEstimate = frame.lightEstimate {
            ambientIntensity = Float(lightEstimate.ambientIntensity) / 1000.0
        }
        
        let ambientLightColor: vector_float3 = vector3(0.5, 0.5, 0.5)
        uniforms.pointee.ambientLightColor = ambientLightColor * ambientIntensity
        //let cd = renderDestination.currentDrawable
        
        
        let drawableSize = renderDestination.drawableSize
        uniforms.pointee.pixelSize = float2(Float(drawableSize.width),Float(drawableSize.height))
        
        var directionalLightDirection : vector_float3 = vector3(0.0, 0.0, -1.0)
        directionalLightDirection = simd_normalize(directionalLightDirection)
        uniforms.pointee.directionalLightDirection = directionalLightDirection
        
        let directionalLightColor: vector_float3 = vector3(0.6, 0.6, 0.6)
        uniforms.pointee.directionalLightColor = directionalLightColor * ambientIntensity
        
        uniforms.pointee.materialShininess = 30
    }
    
    /*
    func updateAnchors(frame: ARFrame) {
       updateCubeAnchor(frame: frame)
    }
    
    func updatePointAnchor(frame: ARFrame) {
        
    }
 
    func updateCapturedImageTextures(frame: ARFrame) {
        
    }
    
    
    
    func drawCapturedImage(renderEncoder: MTLRenderCommandEncoder) {
       
    }
    
    */
}


