Shader "Custom/Water"
{
	Properties
	{
		[Header(Colors)]
		_Color("Shallow Color", color) = (0.6,1,0.8,1)
		_DepthColor("Depth Color", color) = (0,0.26,0.4,1)
		_DepthStart("Depth Start", float) = 0
		_DepthEnd("Depth End", float) = 1
		_Smoothness("Surface Smoothness", range(0,1)) = 0.5
		_Distortion("Underwater Distortion", range(0,128)) = 32	

		[Space(10)]
		[Header(Normals)]
		_NormalMap("Normal Map", 2D) = "bump" {}
		_NormalMapTilings("Normal Map: Tilings", vector) = (1,1,1,1)
		_NormalMapSpeeds("Normal Map: Speeds", vector) = (1,1,0.5,0.5)

		[Space(10)]
		[Header(EdgeFade)]
		_EdgeSize("EdgeFade: Size", float) = 1

		[Space(10)]
		[Header(Foam)]
		_FoamColor("Foam: Color", color) = (1,1,1,1)
		_FoamTex("Foam: Texture", 2D) = "white" {}
		_FoamTiling("Foam: Tiling", vector) = (1,1,1,1)
		_FoamSize("Foam: Size", float) = 0.1
		_FoamDistortion("Foam: Distortion", float) = 0.1

		[Space(10)]
		[Header(Caustics)]
		_CausticsTex("Caustics Texture", 2D) = "black" {}
		_CausticsIntensity("Caustics: Intensity", float) = 4
		_CausticsTiling("Caustics Tiling", vector) = (1,1,1,1)
		_CausticsStart("Caustics: Start", float) = 0
		_CausticsEnd("Caustics: End", float) = 1
		_CausticsSpeed("Caustics: Speed", vector) = (1,1,-1,-1)

		[Space(10)]
		[Header(Scattering)]
		_ScatteringColor("Scattering: Color", color) = (1,1,1,1)
		_ScatteringIntensity("Scattering: Intensity", Float) = 1
		_ScatteringRangeMin("Scattering: Min", Float) = 0
		_ScatteringRangeMax("Scattering: Max", Float) = 1

		[Space(10)]
		[Header(Reflections)]
		_ReflectionFresnel("Reflection: Fresnel", Range(0,16)) = 4
		_ReflectionFresnelNormal("Reflection: Fresnel Normal", Range(0,1)) = 0.25
		_ReflectionIntensity("Reflection: Intensity", Range(0,1)) = 1
		_ReflectionDistortion("Reflection: Distortion", Range(0,1)) = 0.5
		_ReflectionRoughness("Reflection: Roughness", Range(0,1)) = 0.1

		[Space(10)]
		[Header(Wave)]
		_GerstnerSpeed("Wave Speed", float) = 1
		_GerstnerWave("Wave Direction, Steepness, WaveLength ", vector) = (1,0,0.05,4)
		
	}

	SubShader
	{		
		Tags
		{
		"RenderType" = "Transparent"
		"Queue" = "Transparent"
		"RenderPipeline" = "UniversalRenderPipeline"
		}
			
		Blend SrcAlpha OneMinusSrcAlpha

		Pass
		{
			Name "Front"
			Tags { "LightMode" = "UniversalForward" }

			HLSLPROGRAM
			#pragma vertex vert
			#pragma fragment frag					
			#pragma multi_compile_instancing
			#pragma multi_compile_fog
			#pragma target 3.0

			#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"			

			#include "Includes/WaterFog.hlsl"  
			#include "Includes/WaterVariables.hlsl"
			#include "Includes/WaterHelpers.hlsl"
			#include "Includes/WaterLighting.hlsl"
			#include "Includes/WaterCommon.hlsl"
		
			ENDHLSL
		}
	}
}
