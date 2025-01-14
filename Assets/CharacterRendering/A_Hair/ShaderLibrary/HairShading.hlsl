﻿#ifndef HAIRSHADING_INCLUDED
#define HAIRSHADING_INCLUDED
#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"
#include "Packages/com.unity.render-pipelines.core/ShaderLibrary/CommonLighting.hlsl"


real Pow2(real x)
{
    return (x * x);
}

real Pow5(real x)
{
    return (x * x * x * x * x);
}

inline float4 EncodeFloatRGBA( float v )
{
    float4 kEncodeMul = float4(1.0, 255.0, 65025.0, 16581375.0);
    float kEncodeBit = 1.0/255.0;
    float4 enc = kEncodeMul * v;
    enc = frac (enc);
    enc -= enc.yzww * kEncodeBit;
    return enc;
}

//--------------------基本数据准备--------------------
struct HairData
{
    float Alpha[3];
    float B[3];
    float VdotL;
    float SinThetaL;
    float SinThetaV;
    float CosThetaD;
    float CosPhi;
    float CosHalfPhi;
    float n_prime;
};

struct HairSurfaceData
{
    half3 baseColor;
    half id;
    half root;
    half ao;
    half roughness;
    half specular;
    half alpha;
};

struct HairLitData
{
    float3 positionWS;
    half3 V; //ViewDirWS
    half3 N; //NormalWS
    half3 B; //BinormalWS
    half3 T; //TangentWS
    float2 ScreenUV;
};

float Hair_g(float B, float Theta)
{
    return exp(-0.5 * Pow2(Theta) / (B * B)) / (sqrt(2 * PI) * B);
}

float Hair_F(float CosTheta)
{
    const float n = 1.55;
    const float F0 = Pow2((1 - n) / (1 + n));
    return F0 + (1 - F0) * Pow5(1 - CosTheta);
}

void InitalHairData(out HairData hairData, float3 B, float3 V, float3 L, float roughness)
{
    const float Shift = 0.035;
    hairData.Alpha[0] = -Shift * 2; //R_shift
    hairData.Alpha[1] = Shift; //TT_shift
    hairData.Alpha[2] = Shift * 4; //TRT_shift

    float ClampedRoughness = clamp(roughness, 1 / 255.0f, 1.0f);
    hairData.B[0] = Pow2(ClampedRoughness); //R_roughness
    hairData.B[1] = Pow2(ClampedRoughness) / 2; //TT_roughness
    hairData.B[2] = Pow2(ClampedRoughness) * 2; //TRT_roughness

    //N是指向发根的方向
    hairData.VdotL = saturate(dot(V, L));
    hairData.SinThetaL = clamp(dot(B, L), -1.f, 1.f);
    hairData.SinThetaV = clamp(dot(B, V), -1.f, 1.f);
    hairData.CosThetaD = cos(0.5 * abs(FastASin(hairData.SinThetaV) - FastASin(hairData.SinThetaL)));

    const float3 Lp = L - hairData.SinThetaL * B;
    const float3 Vp = V - hairData.SinThetaV * B;
    hairData.CosPhi = dot(Lp, Vp) * rsqrt(dot(Lp, Lp) * dot(Vp, Vp) + 1e-4);
    hairData.CosHalfPhi = sqrt(saturate(0.5 + 0.5 * hairData.CosPhi));

    hairData.n_prime = 1.19 / hairData.CosThetaD + 0.36 * hairData.CosThetaD;
}


//--------------------漫反射项计算--------------------
half3 KajiyaKayDiffuseAttenuation(float3 albedo, half scatter, float3 L, float3 V, half3 B)
{
    // Use soft Kajiya Kay diffuse attenuation
    float KajiyaDiffuse = 1 - abs(dot(B, L));

    float3 FakeNormal = normalize(V - B * dot(V, B));
    B = FakeNormal;

    // Hack approximation for multiple scattering.
    float Wrap = 1;
    float BdotL = saturate((dot(B, L) + Wrap) / Pow2(1 + Wrap));
    float DiffuseScatter = (1 / PI) * lerp(BdotL, KajiyaDiffuse, 0.33) * scatter;
    float Luma = Luminance(albedo);
    float3 ScatterTint = pow(albedo / Luma, 1 - (scatter + 1) * 0.5);
    return sqrt(albedo) * DiffuseScatter * ScatterTint;
}

float3 Diffuse_Lambert(float3 albedo)
{
    return albedo * (1 / PI);
}

half3 HairKajiyaDiffuseTerm(half scatter, float3 albedo, float3 L, float3 V, half3 B)
{
    half3 kkDiffuseAtten = max(KajiyaKayDiffuseAttenuation(albedo, scatter, L, V, B), 0.0);
    return kkDiffuseAtten;
}


//--------------------高光项计算--------------------
half3 R_Function(HairData hairData, float Specular)
{
    const float sa = sin(hairData.Alpha[0]);
    const float ca = cos(hairData.Alpha[0]);
    float Shift = 2 * sa * (ca * hairData.CosHalfPhi * sqrt(1 - Pow2(hairData.SinThetaV)) + sa * hairData.SinThetaV);

    float Mp = Hair_g(hairData.B[0] * sqrt(2.0) * hairData.CosHalfPhi, hairData.SinThetaL + hairData.SinThetaV - Shift);
    float Np = 0.25 * hairData.CosHalfPhi;
    float Fp = Hair_F(sqrt(saturate(0.5 + 0.5 * hairData.VdotL)));
    return Mp * Np * Fp * Specular * 2;
}

half3 TT_Function(HairData hairData, float3 BaseColor)
{
    float a = 1 / hairData.n_prime;
    float h = hairData.CosHalfPhi * (1 + a * (0.6 - 0.8 * hairData.CosPhi));
    float3 Tp = pow(BaseColor, 0.5 * sqrt(1 - Pow2(h * a)) / hairData.CosThetaD);

    float f = Hair_F(hairData.CosThetaD * sqrt(saturate(1 - h * h)));
    float Fp = Pow2(1 - f);

    float Mp = Hair_g(hairData.B[1], hairData.SinThetaL + hairData.SinThetaV - hairData.Alpha[1]);
    float Np = exp(-3.65 * hairData.CosPhi - 3.98);
    return Mp * Np * Fp * Tp;
}

half3 TRT_Function(HairData hairData, float3 BaseColor)
{
    float Mp = Hair_g(hairData.B[2], hairData.SinThetaL + hairData.SinThetaV - hairData.Alpha[2]);

    float f = Hair_F(hairData.CosThetaD * 0.5);
    float Fp = Pow2(1 - f) * f;

    float3 Tp = pow(BaseColor, 0.8 / hairData.CosThetaD);

    float Np = exp(17 * hairData.CosPhi - 16.78);
    return Mp * Np * Fp * Tp;
}

half3 shiftTangent(half3 T, half3 N, half shift)
{
    return normalize(T + shift * N);
}

float KajiyaSpecualr(half3 T, half3 V, half3 L, half specPower, half specularWidth, half specualrScale)
{
    half3 H = normalize(V + L);

    float HdotT = dot(T, H);
    float sinTH = sqrt(1 - HdotT * HdotT);
    float dirAtten = smoothstep(-specularWidth, 0, HdotT);

    return dirAtten * saturate(pow(sinTH, specPower)) * specualrScale;
}

half3 KajiyaKaySpecularTerm(HairLitData hairLitData, Light light, half3 primaryColor, float primaryShift,
                            half3 secondaryColor, float secondaryShift,half specPower,half specularWidth,half specualrScale)
{
    half3 t1 = shiftTangent(hairLitData.B, hairLitData.N, primaryShift);
    half3 t2 = shiftTangent(hairLitData.B, hairLitData.N, secondaryShift);

    half3 specular = half3(0.0, 0.0, 0.0);
    half VoL=saturate(dot(-hairLitData.V,light.direction));
    specular += primaryColor * KajiyaSpecualr(t1, hairLitData.V, light.direction, specPower,specularWidth,specualrScale) ;
    specular += secondaryColor * KajiyaSpecualr(t2, hairLitData.V, light.direction, specPower,specularWidth,specualrScale)*VoL;

    return specular;
}

half3 MachsnerHairSpecularTerm(HairData hairData, half3 BaseColor, float Specular)
{
    half3 R = R_Function(hairData, Specular);
    half3 TT = TT_Function(hairData, BaseColor);
    half3 TRT = TRT_Function(hairData, BaseColor);
    return (R + TT + TRT);
}
#endif
