//
//  Lighting.h
//  ARRay
//
//  Created by David Crooks on 02/09/2020.
//  Copyright © 2020 David Crooks. All rights reserved.
//

#ifndef Lighting_h
#define Lighting_h
#include "SDF.h"

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

float3 diffuseLighting(Trace trace, float3 normal, float3 lightColor,float3 lightDir){
    float lambertian = max(dot(lightDir,normal), 0.0);
    return  lambertian * trace.material.color.diffuse * lightColor;
}

float3 specularLighting(Trace trace, float3 normal, float3 lightColor,float3 lightDir){
    //blinn-phong
    //https://en.wikipedia.org/wiki/Blinn%E2%80%93Phong_shading_model
    float3 viewDir = -trace.ray.direction;
    
    float3 halfDir = normalize(lightDir + viewDir);
    float specAngle = max(dot(halfDir, normal), 0.0);
    float specular = pow(specAngle, trace.material.shininess);
    
    return specular * trace.material.color.specular * lightColor;
}

float3 pointLighting(Trace trace, float3 normal, PointLight light,float3 lightDir,float d){
    
    float3 color =  diffuseLighting(trace, normal, light.color.diffuse, lightDir);
    
    color += specularLighting(trace, normal, light.color.specular, lightDir);
    
    float  attenuation = 1.0 / (1.0 +  0.1 * d * d);
    
    color *= attenuation;
    return  color;
}

float3 pointLighting(Trace trace, float3 normal, PointLight light){
    float3 lightDir = light.position - trace.p;
    float d = length(lightDir);
    lightDir = normalize(lightDir);
    
    return pointLighting(trace, normal, light,lightDir,d);
}



float3 directionalLighting(Trace trace, float3 normal, DirectionalLight light){
    
    float3 color =  diffuseLighting(trace, normal, light.color.diffuse, light.direction);
    
    color += specularLighting(trace, normal, light.color.specular, light.direction);
    
    return  color;
}


#endif /* Lighting_h */
