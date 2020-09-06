# AR-Ray
Augumented Reality iOS app using ARKit and Metal. We use  signed difference functions and ray marching to render an animated liquid metal blob floating in the enviroment. Tap on the screen to place the blob.

![iphone screen shot](iPhone-screentshot.png)

## Signed Distance Functions

Signed Distance Functions (SDF) are a way to describe a 3d object mathematically in terms of the distance from a point to the surface. If the point is outside of the surface, the value is positve, if it is inside the value is negative.  For example, for a sphere we have

``` c
float sphere(float3 p, float3 center, float radius) {
   return distance(p, center) - radius;
}
```
We can use SDFs to find the intersection of light ray with the surface of the object. SDFs can be combined in intersting ways (e.g add, subtract, blend) so that we can create complex shapes without having to use millions of triangles.

## Ray Marching in Augumented Reality

In order to do raymarching with our SDFs in Augumented Reality we need to find a light ray coming from the camera for each pixel in the image. We can obtain the princple rays by unprojecting the four corners of the screen onto a plane in front of the camera.:
``` swift
    let screenPoints = [
                           CGPoint(x: 0.0, y:  size.height),
                           CGPoint(x: size.width, y:  size.height),
                           CGPoint(x: 0.0, y:  0.0),
                           CGPoint(x: size.width, y:  0.0)
                       ]
   
   let spacePoints = screenPoints
                       .compactMap { frame.camera.unprojectPoint($0, ontoPlane: plane, orientation:orientation, viewportSize: size) }
```
Then the normals for the light rays are given by: 

``` swift
    let rayNormals = spacePoints.map {
       return simd_normalize($0-cameraPoition)
   }

```
We can then interpolate in the shader to get all the camera rays and intersect them with our the scene.

## Enviroment Probe
ARKit provides  AREnvironmentProbeAnchor, which we can add to the session to obtain a 
``` swift
let probeAnchor = AREnvironmentProbeAnchor(name:manualProbe.objectProbeAnchorIdentifyer, transform: object.transform, extent: extent)
       session.add(anchor: probeAnchor)
```
We can then get cube map of the enviroment from the probes enviromentTexture property. This tecxture is passed to metal to render the relfections in our metalic blob.
