﻿#ifndef SPHERICAL_GAUSSIAN_SSS_LIT_DATA_INCLUDED
#define SPHERICAL_GAUSSIAN_SSS_LIT_DATA_INCLUDED

struct HairLitData
{
    float3 positionWS;
    half3  V; //ViewDirWS
    half3  NGeometry; //NormalWS
    half3  NMap;
    half3  B; //BinormalWS
    half3  T; //TangentWS
    float2 ScreenUV;
};

struct CustomSurfacedata
{
    half3 albedo;
    half3 specular;
    half3 normalTS;
    half curvature;
    half  metallic;
    half  roughnessLobe1;
    half  roughnessLobe2;
    half  occlusion;
    half  alpha;
    half reflection;
};
#endif