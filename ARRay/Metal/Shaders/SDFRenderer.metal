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
#include "SDF.h"
#include "Lighting.h"

struct Constants {
    float time;
    float3 cameraPosition;
    float aspectRatio;
};

struct Model {
    float3 center;
    float time;
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

Materials createMaterials( ) {
    Materials m;
    
    m.black.color.diffuse = float3(0.0,0.0,0.01);
    m.black.color.specular = float3(0.1,0.1,0.1);
    m.black.shininess = 35.0;
    
    m.white.color.diffuse = 0.75*float3(1.0,1.0,0.9);
    m.white.color.specular = 0.3*float3(1.0,1.0,0.9);
    m.white.shininess = 16.0;
    
    return m;
}

//////////////////////////////////////////////////////////////////////
/////////////////////// Map The Scene ////////////////////////////////

float3 trefoilKnotPath(float r, float t){
    float3 v;
    
    v.x = cos(2.0*t)*(1.0 + r*cos(3.0*t));
    
    v.y = sin(2.0*t)*(1.0 + r*cos(3.0*t));
    
    v.z = r*sin(3.0*t);
    
    return v;
}

MapValue sphereknot(float3 p, float3 c, float radius, Material m,float time) {
      
  MapValue mv;
    
    
  mv.material = m;
  
    const int n = 3;
    
    float sd = 3.0;
    
    float k = 3.0;
    float numerator = 1.0;
    float denominator = 0.0;
    
    for(int i = 0; i < n; i++ ) {
        
        //float t = PI*0.1*float(i) ;
        float m = 3.0*TWO_PI*float(i)/float(n);
        float t = 0.2*time + m;
        
        float3 r = 0.2*trefoilKnotPath(0.5,t);
        
        float s =  distance(p, c+r) - radius;
        
        float a = pow( s,k);
        numerator *= a;
        
        denominator += a;
        
       // sd = min(s,sd);
    }
    
    sd =  pow(numerator/denominator,1.0/k);
   mv.signedDistance = sd;
  return mv;
}

MapValue map(float3 p, Materials m,Model model){
    
    MapValue mainSphere  = sphere(p,model.center,0.2, m.white);
    
    float3 t1 = 0.2*trefoilKnotPath(0.3,model.time);
    MapValue s1  = sphere(p,model.center + t1,0.05, m.white);
    
    float3 t2 = 0.23*trefoilKnotPath(0.2,1.33*model.time).zyx;
    
    MapValue s2  = sphere(p,model.center + t2,0.08, m.white);
    
    
   // MapValue obj2  = sphereknot(p,model.center,0.1, m.white,model.time);
    
    
    return addObjectsSmooth(mainSphere,addObjectsSmooth(s1,s2));
}

//////////////////////////////////////////////////////////////////////
/////////////////////// Raytracing ///////////////////////////////////

float3 calculateNormal(float3 p, Materials m, Model c) {
    float epsilon = 0.001;
    
    float3 normal = float3(
                           map(p +float3(epsilon,0,0),m,c).signedDistance - map(p - float3(epsilon,0,0),m,c).signedDistance,
                           map(p +float3(0,epsilon,0),m,c).signedDistance - map(p - float3(0,epsilon,0),m,c).signedDistance,
                           map(p +float3(0,0,epsilon),m,c).signedDistance - map(p - float3(0,0,epsilon),m,c).signedDistance
                           );
    
    return normalize(normal);
}


Trace traceRay(Ray ray, float maxDistance, Materials m, Model model) {
    float dist = 0.01;
    float presicion = 0.002;
    float3 p;
    MapValue mv;
    bool hit = false;
    for(int i=0; i<64; i++){
        p = rayPoint(ray,dist);
        mv = map(p,m,model);
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

float castShadow(Ray ray, float dist, Materials m, Model model){
    Trace trace = traceRay(ray, dist, m, model);
    float maxDist = min(1.0,dist);
    float result = trace.dist/maxDist;
    
    return clamp(result,0.0,1.0);
}

/////////////////////// Lighting ////////////////////////////////

float3 pointLighting(Trace trace, float3 normal, PointLight light, Materials m,Model model){
    float3 lightDir = light.position - trace.p;
    float d = length(lightDir);
    lightDir = normalize(lightDir);
    float3 color = pointLighting(trace, normal, light,lightDir);
    float shadow = castShadow(Ray(trace.p,lightDir),d,m,model);
    color *= shadow;
    return  color;
}

float3 directionalLighting(Trace trace, float3 normal, DirectionalLight light,Materials m,Model model){
    float3 color = directionalLighting(trace,normal,light);
    float shadow = castShadow(Ray(trace.p,light.direction),3.0,m,model);
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

float3 lighting(Trace trace, float3 normal, Lights lights, Materials m, Model c){
    float3 color = float3(0.75,0.75,0.1);//ambient color
    
    color += pointLighting(trace, normal,lights.light1,m,c);
    color += pointLighting(trace, normal,lights.light2,m,c) ;
    color += pointLighting(trace, normal,lights.light3,m,c) ;
    color += directionalLighting(trace, normal,lights.dirLight,m,c);
    
    return color;
}

float4 render(Ray ray, Materials m, Lights lights,Model model,texturecube<float> cubeTexture ,
              sampler cubeSampler ){

    Trace trace = traceRay(ray,12.0,m,model);
    
    float3 normal = calculateNormal(trace.p,m,model);
    
    float3 reflection = reflect(ray.direction, normal);

    float4 color = cubeTexture.sample(cubeSampler,reflection);

    float alpha = trace.hit ? 1.0 : 0.0 ;
    return float4(color.rgb,alpha);
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

fragment half4 sdfFragmentShader(VertexInOut in [[ stage_in ]],constant SharedUniforms &sharedUniforms [[ buffer(kBufferIndexSharedUniforms) ]],texturecube<float, access::sample> cubeTexture [[texture(kTextureIndexCube)]]) {
    
    Lights lights = createLights(sharedUniforms.time);
    Materials m = createMaterials();
    
    Ray ray = Ray(sharedUniforms.cameraPosition, normalize(in.rayNormal));
    constexpr sampler cubeSampler(mip_filter::linear,
    mag_filter::linear,
    min_filter::linear);
    
    Model model;// = Model(sharedUniforms.objectPosition, sharedUniforms.time);
    model.center = sharedUniforms.objectPosition;
    model.time = sharedUniforms.time;
    float4 colorLinear =  render(ray, m, lights, model,cubeTexture,cubeSampler);
    
    float screenGamma = 2.2 ;
    float3 colorGammaCorrected = pow(colorLinear.rgb, float3(1.0/screenGamma));
    half3 h = half3(colorGammaCorrected);
    return half4(h,colorLinear.a);
    
}


