//
//  SDFRenderer.metal
//  ARRay
//
//  Created by David Crooks on 15/02/2019.
//  Copyright © 2019 David Crooks. All rights reserved.
//

#include <metal_stdlib>
using namespace metal;
#import "ShaderTypes.h"

struct Constants {
    float time;
    float3 cameraPosition;
    float aspectRatio;
};

struct Ray {
    float3 origin;
    float3 direction;
    
    Ray(float3 origin,float3 direction):origin(origin),
    direction(direction) {}
};

struct LightColor {
    float3 diffuse;
    float3 specular;
    // LightColor();
    
    LightColor( ):
    diffuse(float3()),
    specular(float3()) {}
    
    
    LightColor( float3 diffuse, float3 specular):
    diffuse(diffuse),
    specular(specular) {}
};

struct Material {
    LightColor  color;
    float shininess;
};

struct MapValue {
    float       signedDistance;
    Material  material;
};

struct Trace {
    float    dist;
    float3     p;
    Ray      ray;
    Material material;
    bool hit;
    
    Trace(float dist, float3 p,Ray ray, Material material,bool hit): dist(dist),
    p(p),
    ray(ray),
    material(material),
    hit(hit)  {}
};


struct PointLight {
    float3 position;
    LightColor color;
    
    PointLight()    :
    position(float3()),
    color(LightColor()) {}
    
    PointLight(float3 position,LightColor color)    :
    position(position),
    color(color) {}
};

struct DirectionalLight {
    float3 direction;
    LightColor color;
    
    //  DirectionalLight();
    
    DirectionalLight():
    direction(float3()),
    color(LightColor()) {}
    
    DirectionalLight(float3 direction,LightColor color) :
    direction(direction),
    color(color) {}
};

struct Materials {
    Material black;
    Material white;
};

struct Lights {
    PointLight  light1;
    PointLight light2;
    PointLight light3;
    DirectionalLight dirLight;
    
    Lights():   light1(PointLight()),
    light2(PointLight()),
    light3(PointLight()),
    dirLight(DirectionalLight()){}
    
};

/*
 PointLight  light1,light2,light3;
 DirectionalLight dirLight;
 
 Material blackMat,whiteMat,bluishMat,yellowMat,oscMat,tableMat,tableDarkMat;
 
 */

float3 rayPoint(Ray r,float t) {
    return r.origin +  t*r.direction;
}



MapValue intersectObjects( MapValue d1, MapValue d2 )
{
    if (d1.signedDistance>d2.signedDistance){
        return    d1 ;
    }
    else {
        d2.material = d1.material;
        return d2;
    }
}

Materials createMaterials( ) {
    Materials m;
    
    m.black.color.diffuse = float3(0.0,0.0,0.01);
    m.black.color.specular = float3(0.1,0.1,0.1);
    m.black.shininess = 35.0;
    
    m.white.color.diffuse = 0.75*float3(1.0,1.0,0.9);
    m.white.color.specular = 0.3*float3(1.0,1.0,0.9);
    m.white.shininess = 16.0;
    
    //blackMat = Material(LightColor(float3(0.0,0.0,0.01),float3(0.1,0.1,0.1)) , 35.0);
    //whiteMat = Material(LightColor(0.75*float3(1.0,1.0,0.9),0.3*float3(1.0,1.0,0.9)) ,shininess );
    
    
    return m;
}



/////////////////////////   SDFs   ///////////////////////////////////

MapValue cube( float3 p, float d , Material m)
{
    MapValue mv;
    mv.material = m;
    mv.signedDistance = length(max(abs(p) -d,0.0));
    return mv;
}

MapValue xzPlane( float3 p ,float y, Material m)
{
    MapValue mv;
    mv.material = m;
    mv.signedDistance = p.y - y;
    return mv;
}

MapValue plane(float3 p, float3 origin, float3 normal , Material m ){
    float3 a = p - origin;
    MapValue mv;
    mv.material = m;
    mv.signedDistance = dot(a,normal);
    return mv;
}

MapValue sphere(float3 p, float3 center, float radius, Material m) {
    MapValue mv;
    mv.material = m;
    mv.signedDistance = distance(p, center) - radius;
    return mv;
}

//////////////////////////////////////////////////////////////////////
/////////////////////// Map The Scene ////////////////////////////////

MapValue map(float3 p, Materials m,float3 center){
    
    MapValue obj  = sphere(p,center,0.2, m.white);
    
    return obj;
}


//////////////////////////////////////////////////////////////////////
/////////////////////// Raytracing ///////////////////////////////////

float3 calculateNormal(float3 p, Materials m, float3 c) {
    float epsilon = 0.001;
    
    float3 normal = float3(
                           map(p +float3(epsilon,0,0),m,c).signedDistance - map(p - float3(epsilon,0,0),m,c).signedDistance,
                           map(p +float3(0,epsilon,0),m,c).signedDistance - map(p - float3(0,epsilon,0),m,c).signedDistance,
                           map(p +float3(0,0,epsilon),m,c).signedDistance - map(p - float3(0,0,epsilon),m,c).signedDistance
                           );
    
    return normalize(normal);
}


Trace traceRay(Ray ray, float maxDistance, Materials m, float3 center) {
    float dist = 0.01;
    float presicion = 0.002;
    float3 p;
    MapValue mv;
    bool hit = false;
    for(int i=0; i<64; i++){
        p = rayPoint(ray,dist);
        mv = map(p,m,center);
        dist += 0.5*mv.signedDistance;
        if(mv.signedDistance < presicion) {
            hit = true;
            break;
        }
        if(dist>maxDistance) {
            break;
        }
        
    }
    
    return Trace(dist,p,ray,mv.material,hit);
}

float castShadow(Ray ray, float dist, Materials m, float3 center){
    Trace trace = traceRay(ray, dist, m, center);
    float maxDist = min(1.0,dist);
    float result = trace.dist/maxDist;
    
    return clamp(result,0.0,1.0);
}
/*
Ray cameraRay(float3 viewPoint, float3 lookAtCenter, float2 p , float d){
    float3 v = normalize(lookAtCenter -viewPoint);
    
    float3 n1 = cross(v,float3(0.0,1.0,0.0));
    float3 n2 = cross(n1,v);
    
    float3 lookAtPoint = lookAtCenter + d*(p.y*n2 + p.x*n1);
    
    Ray ray(viewPoint,normalize(lookAtPoint - viewPoint) );
    
    //ray.origin = viewPoint;
    //ray.direction =  normalize(lookAtPoint - viewPoint);
    
    return ray;
}
*/
/////////////////////// Lighting ////////////////////////////////

float3 diffuseLighting(Trace trace, float3 normal, float3 lightColor,float3 lightDir){
    float lambertian = max(dot(lightDir,normal), 0.0);
    return  lambertian * trace.material.color.diffuse * lightColor;
}

float3 specularLighting(Trace trace, float3 normal, float3 lightColor,float3 lightDir, Materials m){
    //blinn-phong
    //https://en.wikipedia.org/wiki/Blinn%E2%80%93Phong_shading_model
    float3 viewDir = -trace.ray.direction;
    
    float3 halfDir = normalize(lightDir + viewDir);
    float specAngle = max(dot(halfDir, normal), 0.0);
    float specular = pow(specAngle, trace.material.shininess);
    
    return specular * trace.material.color.specular * lightColor;
}


float3 pointLighting(Trace trace, float3 normal, PointLight light, Materials m,float3 center){
    float3 lightDir = light.position - trace.p;
    float d = length(lightDir);
    lightDir = normalize(lightDir);
    
    float3 color =  diffuseLighting(trace, normal, light.color.diffuse, lightDir);
    
    color += specularLighting(trace, normal, light.color.specular, lightDir, m);
    
    float  attenuation = 1.0 / (1.0 +  0.1 * d * d);
    float shadow = castShadow(Ray(trace.p,lightDir),d,m,center );
    color *= attenuation*shadow;
    return  color;
}

float3 directionalLighting(Trace trace, float3 normal, DirectionalLight light,Materials m,float3 center){
    
    float3 color =  diffuseLighting(trace, normal, light.color.diffuse, light.direction);
    
    color += specularLighting(trace, normal, light.color.specular, light.direction,  m);
    
    float shadow = castShadow(Ray(trace.p,light.direction),3.0,m,center);
    color *= shadow;
    return  color;
}

Lights createLights(float time){
    float3 specular = float3(0.7);
    Lights lights;
    lights.light1 = PointLight(float3(cos(1.3*time),1.0,sin(1.3*time)),LightColor( float3(0.7),specular));
    lights.light2 = PointLight(float3(0.7*cos(1.6*time),1.1+ 0.35*sin(0.8*time),0.7*sin(1.6*time)),LightColor(float3(0.6),specular));
    lights.light3 = PointLight(float3(1.5*cos(1.6*time),0.15+ 0.15*sin(2.9*time),1.5*sin(1.6*time)),LightColor(float3(0.6),specular));
    lights.dirLight = DirectionalLight(normalize(float3(0.0,1.0,0.0)),LightColor(float3(0.1),float3(0.5)));
    return lights;
}

float3 lighting(Trace trace, float3 normal, Lights lights, Materials m, float3 c){
    float3 color = float3(0.75,0.75,0.1);//ambient color
    
    color += pointLighting(trace, normal,lights.light1,m,c);
    color += pointLighting(trace, normal,lights.light2,m,c) ;
    color += pointLighting(trace, normal,lights.light3,m,c) ;
    color += directionalLighting(trace, normal,lights.dirLight,m,c);
    
    return color;
}

float4 render(Ray ray, Materials m, Lights lights,float3 center){

    Trace trace = traceRay(ray,12.0,m,center);
    
    float3 normal = calculateNormal(trace.p,m,center);
    float3 color = lighting(trace,normal,lights,m,center);
    float alpha = trace.hit ? 1.0 : 0.0 ;
    return float4(color,alpha);
}

typedef struct {
    float2 position [[attribute(0)]];
    float3 rayNormal [[attribute(1)]];
} RayPlaneVertex;

struct VertexInOut {
    float4 position [[ position ]];
    float3 rayNormal;
};

struct VertexIn {
    float2 position [[attribute(0)]];
};

vertex VertexInOut sdfVertexShader(RayPlaneVertex in [[stage_in]])  {
   
    VertexInOut out;
    // Pass through the image vertex's position
    out.position = float4(in.position, 0.0, 1.0);
    
    // Pass through the rayNormal
    out.rayNormal= in.rayNormal;
    
    return out;
}

fragment half4 sdfFragmentShader(VertexInOut in [[ stage_in ]],constant SharedUniforms &sharedUniforms [[ buffer(kBufferIndexSharedUniforms) ]]) {
    
    Lights lights = createLights(sharedUniforms.time);
    Materials m = createMaterials();
    
    Ray ray = Ray(sharedUniforms.cameraPosition, normalize(in.rayNormal));
    
    float4 colorLinear =  render(ray, m, lights, sharedUniforms.objectPosition);
    
    float screenGamma = 2.2;
    float3 colorGammaCorrected = pow(colorLinear.rgb, float3(1.0/screenGamma));
    half3 h = half3(colorGammaCorrected);
    return half4(h,colorLinear.a);
    
}


