//
//  ARMetalDrawable.swift
//  ARMetalTest
//
//  Created by David Crooks on 12/02/2019.
//  Copyright © 2019 David Crooks. All rights reserved.
//

import Foundation
import ARKit
import MetalKit

protocol ARMetalDrawable {
    var pipelineState: MTLRenderPipelineState? { get set }
    var renderDestination:RenderDestinationProvider { get set }
    func update(frame: ARFrame)
    func draw(renderEncoder: MTLRenderCommandEncoder, sharedUniformBuffer: MTLBuffer, sharedUniformBufferOffset:Int )
}
