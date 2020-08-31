//
//  Util.swift
//  RayBreak
//
//  Created by David Crooks on 08/02/2019.
//  Copyright © 2019 caroline. All rights reserved.
//

import Foundation


extension Array {
    var byteLength:Int {
        return count * MemoryLayout<Element>.stride
    }
}
