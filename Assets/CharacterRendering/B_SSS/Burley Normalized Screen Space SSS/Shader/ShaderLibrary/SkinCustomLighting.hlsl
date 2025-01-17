﻿#ifndef SSSSS_SKIN_LITGHTING_INCLUDED
#define SSSSS_SKIN_LITGHTING_INCLUDED

#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"
#include "Packages/com.unity.render-pipelines.core/ShaderLibrary/CommonLighting.hlsl"

#define CUSTOM_NAMESPACE_START(namespace) struct _##namespace {
#define CUSTOM_NAMESPACE_CLOSE(namespace) }; _##namespace namespace;

CUSTOM_NAMESPACE_START(Common)
    inline float Pow2(half x)
    {
        return x * x;
    }

    inline float Pow4(half x)
    {
        return x * x * x * x;
    }

    inline float Pow5(half x)
    {
        return x * x * x * x * x;
    }

    inline half3 RotateDirection(half3 R, half degrees)
    {
        float3 reflUVW = R;
        half theta = degrees * PI / 180.0f;
        half costha = cos(theta);
        half sintha = sin(theta);
        reflUVW = half3(reflUVW.x * costha - reflUVW.z * sintha, reflUVW.y, reflUVW.x * sintha + reflUVW.z * costha);
        return reflUVW;
    }

CUSTOM_NAMESPACE_CLOSE(Common)

CUSTOM_NAMESPACE_START(BxDF)
    ////-----------------------------------------------------------  D  -------------------------------------------------------------------
    // GGX / Trowbridge-Reitz
    // [Walter et al. 2007, "Microfacet models for refraction through rough surfaces"]
    float D_GGX_UE5(float a2, float NoH)
    {
        float d = (NoH * a2 - NoH) * NoH + 1; // 2 mad
        return SafeDiv(a2,PI * d * d); // 4 mul, 1 rcp
    }

    ////-----------------------------------------------------------  D  -------------------------------------------------------------------

    //----------------------------------------------------------- Vis ----------------------------------------------------------------
    float Vis_Implicit()
    {
        return 0.25;
    }

    // Appoximation of joint Smith term for GGX
    // [Heitz 2014, "Understanding the Masking-Shadowing Function in Microfacet-Based BRDFs"]
    float Vis_SmithJointApprox(float a2, float NoV, float NoL)
    {
        float a = sqrt(a2);
        float Vis_SmithV = NoL * (NoV * (1 - a) + a);
        float Vis_SmithL = NoV * (NoL * (1 - a) + a);
        return 0.5 * rcp(Vis_SmithV + Vis_SmithL);
    }

    //----------------------------------------------------------- Vis ----------------------------------------------------------------

    //-----------------------------------------------------------  F -------------------------------------------------------------------
    float3 F_None(float3 SpecularColor)
    {
        return SpecularColor;
    }

    // [Schlick 1994, "An Inexpensive BRDF Model for Physically-Based Rendering"]
    float3 F_Schlick_UE5(float3 SpecularColor, float VoH)
    {
        float Fc = Common.Pow5(1 - VoH); // 1 sub, 3 mul
        //return Fc + (1 - Fc) * SpecularColor;		// 1 add, 3 mad

        // Anything less than 2% is physically impossible and is instead considered to be shadowing
        return saturate(50.0 * SpecularColor.g) * Fc + (1 - Fc) * SpecularColor;
    }

    //-----------------------------------------------------------  F -------------------------------------------------------------------

    float3 Diffuse_Lambert(float3 DiffuseColor)
    {
        return DiffuseColor * (1 / PI);
    }

    half3 EnvBRDFApprox(half3 SpecularColor, half Roughness, half NoV)
    {
        // [ Lazarov 2013, "Getting More Physical in Call of Duty: Black Ops II" ]
        // Adaptation to fit our G term.
        const half4 c0 = {-1, -0.0275, -0.572, 0.022};
        const half4 c1 = {1, 0.0425, 1.04, -0.04};
        half4 r = Roughness * c0 + c1;
        half a004 = min(r.x * r.x, exp2(-9.28 * NoV)) * r.x + r.y;
        half2 AB = half2(-1.04, 1.04) * a004 + r.zw;

        // Anything less than 2% is physically impossible and is instead considered to be shadowing
        // Note: this is needed for the 'specular' show flag to work, since it uses a SpecularColor of 0
        AB.y *= saturate(50.0 * SpecularColor.g);

        return SpecularColor * AB.x + AB.y;
    }

    float3 SpecularGGX(float a2, float3 specular, float NoH, float NoV, float NoL, float VoH)
    {
        float D = D_GGX_UE5(a2, NoH);
        float Vis = Vis_SmithJointApprox(a2, NoV, NoL);
        float3 F = F_Schlick_UE5(specular, VoH);
        return (D * Vis) * F;
    }

    half3 StandardBRDF(HairLitData customLitData, CustomSurfacedata customSurfaceData, half3 L, half3 lightColor,
                       float shadow)
    {
        float a2Lobe1 = Common.Pow4(customSurfaceData.roughnessLobe1);
        float a2Lobe2 = Common.Pow4(customSurfaceData.roughnessLobe2);

        float3 H = normalize(customLitData.V + L);
        float NoH = saturate(dot(customLitData.N, H));
        float NoV = max(dot(customLitData.N, customLitData.V), 0.001);
        float NoL = saturate(dot(customLitData.N, L));
        float VoH = saturate(dot(customLitData.V, H)); //LoH
        float3 radiance = NoL * lightColor * shadow * PI; //这里给PI是为了和Unity光照系统统一

        float3 diffuseTerm = Diffuse_Lambert(customSurfaceData.albedo);

        #if defined(_SKINDIFFUSE_ON)
            return diffuseTerm*radiance;
        #endif
        float3 specularTermLobe1 = SpecularGGX(a2Lobe1, customSurfaceData.specular, NoH, NoV, NoL, VoH);
        float3 specularTermLobe2 = SpecularGGX(a2Lobe2, customSurfaceData.specular, NoH, NoV, NoL, VoH);
        float3 specularTerm = lerp(specularTermLobe1, specularTermLobe2, 0.5)*customSurfaceData.reflection;
        #if defined(_SKINSPECULAR_ON)
		    return specularTerm*radiance;
        #endif
        return 0;
    }

    half3 EnvBRDF(HairLitData customLitData, CustomSurfacedata customSurfaceData, float envRotation,
                  float3 positionWS)
    {
        half NoV = max(dot(customLitData.N, customLitData.V), 0.01); //区分正反面
        half3 R = reflect(-customLitData.V, customLitData.N);
        R = Common.RotateDirection(R, envRotation);

        //SH
        float3 diffuseAO = GTAOMultiBounce(customSurfaceData.occlusion, customSurfaceData.albedo);
        float3 radianceSH = SampleSH(customLitData.N);

        float3 indirectDiffuseTerm = radianceSH * customSurfaceData.albedo * diffuseAO;

        #if defined(_SKINDIFFUSE_ON)
        return indirectDiffuseTerm;
        #endif

        float roughness = (customSurfaceData.roughnessLobe1 + customSurfaceData.roughnessLobe2) * 0.5;
        //IBL
        //The Split Sum: 1nd Stage
        half3 specularLD = GlossyEnvironmentReflection(R, positionWS, roughness, customSurfaceData.occlusion);
        //The Split Sum: 2nd Stage
        half3 specularDFG = EnvBRDFApprox(customSurfaceData.specular, roughness, NoV) * customSurfaceData.reflection;
        //AO 处理漏光
        float specularOcclusion = GetSpecularOcclusionFromAmbientOcclusion(NoV, customSurfaceData.occlusion, roughness);
        float3 specularAO = GTAOMultiBounce(specularOcclusion, customSurfaceData.specular);

        float3 indirectSpecularTerm = specularLD * specularDFG * specularAO;
        #if defined(_SKINSPECULAR_ON)
            return indirectSpecularTerm;
        #endif
        return 0;
    }

CUSTOM_NAMESPACE_CLOSE(BxDF)

CUSTOM_NAMESPACE_START(DirectLighting)
    half3 StandardShading(HairLitData customLitData, CustomSurfacedata customSurfaceData, float3 positionWS,
                          float4 shadowCoord)
    {
        half3 directLighting = (half3)0;
        #if defined(_MAIN_LIGHT_SHADOWS_SCREEN) && !defined(_SURFACE_TYPE_TRANSPARENT)
        	float4 positionCS = TransformWorldToHClip(positionWS);
            shadowCoord = ComputeScreenPos(positionCS);
        #else
        shadowCoord = TransformWorldToShadowCoord(positionWS);
        #endif
        //urp shadowMask是用来考虑烘焙阴影的,因为这里不考虑烘焙阴影所以直接给1
        half4 shadowMask = (half4)1.0;

        //main light
        float3 directLighting_MainLight = (half3)0;
        {
            Light light = GetMainLight(shadowCoord, positionWS, shadowMask);
            float3 L = light.direction;
            half3 lightColor = light.color;
            //SSAO
            #if defined(_SCREEN_SPACE_OCCLUSION)
                AmbientOcclusionFactor aoFactor = GetScreenSpaceAmbientOcclusion(customLitData.ScreenUV);
                lightColor *= aoFactor.directAmbientOcclusion;
            #endif
            half shadow = light.shadowAttenuation;
            directLighting_MainLight = BxDF.StandardBRDF(customLitData, customSurfaceData, L, lightColor, shadow);
        }

        //add light
        half3 directLighting_AddLight = (half3)0;
        #ifdef _ADDITIONAL_LIGHTS
        int pixelLightCount = GetAdditionalLightsCount();
        for(int lightIndex = 0; lightIndex < pixelLightCount ; lightIndex++) 
        {
            Light light = GetAdditionalLight(lightIndex,positionWS,shadowMask);
            half3 L = light.direction;
            half3 lightColor = light.color;
            half shadow = light.shadowAttenuation * light.distanceAttenuation;
            directLighting_AddLight += BxDF.StandardBRDF(customLitData,customSurfaceData,L,lightColor,shadow);                                   
        }
        #endif
        return directLighting_MainLight + directLighting_AddLight;
    }


CUSTOM_NAMESPACE_CLOSE(DirectLighting)

CUSTOM_NAMESPACE_START(InDirectLighting)
    half3 EnvShading(HairLitData customLitData, CustomSurfacedata customSurfaceData, float envRotation,
                     float3 positionWS)
    {
        half3 inDirectLighting = (half3)0;

        inDirectLighting = BxDF.EnvBRDF(customLitData, customSurfaceData, envRotation, positionWS);

        return inDirectLighting;
    }

CUSTOM_NAMESPACE_CLOSE(InDirectLighting)

CUSTOM_NAMESPACE_START(PBR)
    half4 StandardLit(HairLitData customLitData, CustomSurfacedata customSurfaceData, float3 positionWS,
                      float4 shadowCoord, float envRotation)
    {
        float3 albedo = customSurfaceData.albedo;
        customSurfaceData.albedo = lerp(customSurfaceData.albedo, float3(0.0, 0.0, 0.0), customSurfaceData.metallic);
        customSurfaceData.specular = lerp(float3(0.028, 0.028, 0.028), albedo, customSurfaceData.metallic);
        half3x3 TBN = half3x3(customLitData.T, customLitData.B, customLitData.N);
        customLitData.N = normalize(mul(customSurfaceData.normalTS, TBN));

        //SSAO
        #if defined(_SCREEN_SPACE_OCCLUSION)
            AmbientOcclusionFactor aoFactor = GetScreenSpaceAmbientOcclusion(customLitData.ScreenUV);
            customSurfaceData.occlusion = min(customSurfaceData.occlusion,aoFactor.indirectAmbientOcclusion);
        #endif

        //DirectLighting
        half3 directLighting = DirectLighting.
            StandardShading(customLitData, customSurfaceData, positionWS, shadowCoord);
        //IndirectLighting
        half3 inDirectLighting = InDirectLighting.EnvShading(customLitData, customSurfaceData, envRotation, positionWS);
        return half4(directLighting + inDirectLighting, 1);
    }

CUSTOM_NAMESPACE_CLOSE(PBR)

#endif
