//
//  SDF.h
//  ARRay
//
//  Created by David Crooks on 02/09/2020.
//  Copyright © 2020 David Crooks. All rights reserved.
//

#ifndef SDF_h
#define SDF_h
#include <metal_stdlib>
using namespace metal;

#define TWO_PI 6.283185
#define PI 3.14159265359
//Golden mean and inverse -  for the icosohedron and dodecadron
#define PHI 1.6180339887
#define INV_PHI 0.6180339887

struct Ray {
    float3 origin;
    float3 direction;
    Ray():origin(float3(0.0)),
    direction(float3(0.0)) {}
    
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
    Ray reflection;
    float3 normal;
    
    
    Trace(float dist, float3 p,Ray ray, Material material,bool hit): dist(dist),
    p(p),
    ray(ray),
    material(material),
    hit(hit)  {}
};

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

MapValue addObjects(MapValue d1, MapValue d2 )
{
    if (d1.signedDistance<d2.signedDistance) {
        return    d1 ;
    }
    else {
        return d2;
    }
}

MapValue subtractObjects( MapValue A, MapValue B )
{
    //A-B
    if (-B.signedDistance>A.signedDistance){
        B.signedDistance *= -1.0;
        B.material = A.material;
        return    B ;
    }
    else {
       
        return A;
    }
}

float smoothmin(float a, float b, float k)
{
    float x = exp(-k * a);
    float y = exp(-k * b);
    return (a * x + b * y) / (x + y);
}

float smoothmin2( float a, float b, float k )
{
    float h = clamp( 0.5+0.5*(b-a)/k, 0.0, 1.0 );
    return mix( b, a, h ) - k*h*(1.0-h);
}

float smoothmax(float a, float b, float k)
{
    return smoothmin( a,  b, -k);
}

MapValue addObjectsSmooth(MapValue d1, MapValue d2 )
{
    float sd = smoothmin(d1.signedDistance,d2.signedDistance,3.0);
    MapValue mv;
      mv.material = d1.material;
      mv.signedDistance = sd;
    return mv;
}

float3x3 rotationMatrix(float3 axis, float angle)
{
    //http://www.neilmendoza.com/glsl-rotation-about-an-arbitrary-axis/
    axis = normalize(axis);
    float s = sin(angle);
    float c = cos(angle);
    float oc = 1.0 - c;
    
    return float3x3(oc * axis.x * axis.x + c,           oc * axis.x * axis.y - axis.z * s,  oc * axis.z * axis.x + axis.y * s,
                oc * axis.x * axis.y + axis.z * s,  oc * axis.y * axis.y + c,           oc * axis.y * axis.z - axis.x * s,
                oc * axis.z * axis.x - axis.y * s,  oc * axis.y * axis.z + axis.x * s,  oc * axis.z * axis.z + c);
}

float  plane(float3 p, float3 origin, float3 normal){
   return dot(p - origin,normal);
}

float  doubleplane(float3 p, float3 origin, float3 normal){
   return max(dot(p - origin,normal),dot(-p - origin,normal));
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


MapValue tetrahedron(float3 p, float d, Material m) {
    
  MapValue mv;
  mv.material = m;
 
  float dn =1.0/sqrt(3.0);
  
   //The tetrahedran is the intersection of four planes:
    float sd1 = plane(p,float3(d,d,d) ,float3(-dn,dn,dn)) ;
    float sd2 = plane(p,float3(d,-d,-d) ,float3(dn,-dn,dn)) ;
     float sd3 = plane(p,float3(-d,d,-d) ,float3(dn,dn,-dn)) ;
     float sd4 = plane(p,float3(-d,-d,d) ,float3(-dn,-dn,-dn)) ;
  
    //max intersects shapes
    mv.signedDistance = max(max(sd1,sd2),max(sd3,sd4));
  return mv;
}


MapValue octahedron(float3 p,  float d, Material m) {
 
  //The octahedron is the intersection of two dual tetrahedra.
  MapValue mv = tetrahedron(p,d,m);
  MapValue mv2 = tetrahedron(-p,d,m);
  
  mv = intersectObjects(mv,mv2);
    
  return mv;
}

MapValue alternativeOctahedron(float3 p,  float d, Material m) {
   //Alternative construction of octahedran.
   //The same as for a terahedron, except intersecting double planes (the volume between two paralell planes).
    
    MapValue mv;
    mv.material = m;
 
    float dn =1.0/sqrt(3.0);
    float sd1 = doubleplane(p,float3(d,d,d) ,float3(-dn,dn,dn)) ;
    float sd2 = doubleplane(p,float3(d,-d,-d) ,float3(dn,-dn,dn)) ;
     float sd3 = doubleplane(p,float3(-d,d,-d) ,float3(dn,dn,-dn)) ;
     float sd4 = doubleplane(p,float3(-d,-d,d) ,float3(-dn,-dn,-dn)) ;
    
    mv.signedDistance = max(max(sd1,sd2),max(sd3,sd4));
  return mv;
}



MapValue dodecahedron(float3 p,  float d, Material m) {
  
    MapValue mv;
    mv.material = m;

    //Some vertices of the icosahedron.
    //The other vertices are cyclic permutations of these, plus the opposite signs.
    //We don't need the opposite sign because we are using double planes - two faces for the price of one.
    float3 v = normalize(float3(0.0,1.0,PHI));
    float3 w = normalize(float3(0.0,1.0,-PHI));
       
    //The dodecahedron is dual to the icosahedron. The faces of one corespond to the vertices of the oyther.
    //So we can construct the dodecahedron by intersecting planes passing through the vertices of the icosohedran.
    float ds = doubleplane(p,d*v,v);
    //max == intesect objects
    ds = max(doubleplane(p,d*w,w),ds);

    ds = max(doubleplane(p,d*v.zxy,v.zxy),ds);
    ds = max(doubleplane(p,d*v.yzx,v.yzx),ds);


    ds = max(doubleplane(p,d*w.zxy,w.zxy),ds);
    ds = max(doubleplane(p,d*w.yzx,w.yzx),ds);
    
    mv.signedDistance = ds;
  
       
    return mv;
}


MapValue icosahedron(float3 p,  float d, Material m) {
  
      MapValue mv;
      mv.material = m;
      float h=1.0/sqrt(3.0);
    
    
    //Same idea as above, using the vertices of the dodecahedron
    float3 v1 = h* float3(1.0,1.0,1.0);
    float3 v2 = h* float3(-1.0,1.0,1.0);
    float3 v3 = h* float3(-1.0,1.0,-1.0);
    float3 v4 = h* float3(1.0,1.0,-1.0);
   
    float3 v5 = h* float3(0.0,INV_PHI,PHI);
    float3 v6 = h* float3(0.0,INV_PHI,-PHI);
    
    float ds = doubleplane(p,d*v1,v1);
    //max == intesect objects
     ds = max(doubleplane(p,d*v2,v2),ds);
    ds = max(doubleplane(p,d*v3,v3),ds);
    ds = max(doubleplane(p,d*v4,v4),ds);
    ds = max(doubleplane(p,d*v5,v5),ds);
    ds = max(doubleplane(p,d*v6,v6),ds);
    
    //plus cyclic permutaions of v5 and v6:
    ds = max(doubleplane(p,d*v5.zxy,v5.zxy),ds);
    ds = max(doubleplane(p,d*v5.yzx,v5.yzx),ds);
    ds = max(doubleplane(p,d*v6.zxy,v6.zxy),ds);
    ds = max(doubleplane(p,d*v6.yzx,v6.yzx),ds);
    
    mv.signedDistance = ds;
    
      return mv;
}
#endif /* SDF_h */
