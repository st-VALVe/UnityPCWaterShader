#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"
#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/ShaderGraphFunctions.hlsl"

#if defined(UNITY_STEREO_INSTANCING_ENABLED) || defined(UNITY_STEREO_MULTIVIEW_ENABLED)
	#define UNITY_DECLARE_SCREENSPACE_TEXTURE(textureName) TEXTURE2D_ARRAY(textureName);
	#define UNITY_DECLARE_SCREENSPACE_TEXTURE_FLOAT(textureName) TEXTURE2D_ARRAY_FLOAT(textureName);
	#define UNITY_SAMPLE_SCREENSPACE_TEXTURE(tex, samplerName, uv) SAMPLE_TEXTURE2D_ARRAY(tex, samplerName, uv.xy, (float)unity_StereoEyeIndex);
	#define UNITY_SAMPLE_TEXTURE2D_LOD(textureName, samplerName, coord2, lod) SAMPLE_TEXTURE2D_ARRAY_LOD(textureName, samplerName, coord2, (float)unity_StereoEyeIndex, lod);
#else
	#define UNITY_DECLARE_SCREENSPACE_TEXTURE(tex) TEXTURE2D(tex);
	#define UNITY_DECLARE_SCREENSPACE_TEXTURE_FLOAT(tex) TEXTURE2D_FLOAT(tex);
	#define UNITY_SAMPLE_SCREENSPACE_TEXTURE(tex, samplerName, uv) SAMPLE_TEXTURE2D(tex, samplerName, uv);
	#define UNITY_SAMPLE_TEXTURE2D_LOD(tex, samplerName, coord2, lod) SAMPLE_TEXTURE2D_LOD(tex, samplerName, coord2, lod);
#endif

TEXTURE2D(_CausticsTex);
TEXTURE2D(_FoamTex);
TEXTURE2D(_NormalMap);

TEXTURE2D(_RefractionColor);

SAMPLER(sampler_CameraOpaqueTexture_linear_clamp);
SAMPLER(sampler_ScreenTextures_linear_clamp);
SAMPLER(sampler_pointTextures_point_clamp);

TEXTURE2D(_ReflectionTexture);

SamplerState Trilinear_repeat_sampler;
SamplerState Linear_repeat_sampler;
SamplerState Linear_clamp_sampler;

float4 _CameraOpaqueTexture_TexelSize;
float4 _CameraDepthTexture_TexelSize;

CBUFFER_START(UnityPerMaterial)

float4 _NormalMap_ST;
float4 _NormalMapSpeeds;
float4 _NormalMapTilings;
float4 _CausticsTiling;
float4 _Color;
float4 _DepthColor;
float4 _CausticsSpeed;
float4 _CausticsSpeed3D;
float4 _ScatteringColor;
float4 _FoamColor;
float4 _FoamTiling;
float4 _GerstnerWave;

float _CausticsStart;
float _CausticsEnd;
float _Distortion;
float _Smoothness;
float _FlowSpeed;
float _FlowIntensity;
float _DepthStart;
float _DepthEnd;
float _ReflectionDistortion;
float _ReflectionFresnelNormal;
float _ReflectionRoughness;
float _EdgeSize;
float _CausticsIntensity;
float _ReflectionFresnel;
float _ReflectionIntensity;
float _FoamSize;
float _FoamDistortion;
float _ScatteringIntensity;
float _ScatteringRangeMin;
float _ScatteringRangeMax;
float _GerstnerSpeed;

CBUFFER_END


struct Attributes
{
	float4 vertex		: POSITION;
	float4 color		: COLOR;
	float3 normal		: NORMAL;
	float4 tangent 		: TANGENT;
	float2 texcoord		: TEXCOORD0;
	float waveHeight	: TEXCOORD1;

	UNITY_VERTEX_INPUT_INSTANCE_ID
};

struct Varyings
{
	float4 pos				: SV_POSITION;
	float4 color			: COLOR;
	float3 worldNormal		: NORMAL;

	float4 texcoord			: TEXCOORD0;
	float4 texcoord1		: TEXCOORD1;
	//  X: Far Distance, Y: Waves Height Z: W:
	float4 texcoord3 : TEXCOORD3;

	float4 screenCoord	: TEXCOORD4;

	half4 normal	: TEXCOORD5;    // xyz: normal, w: viewDir.x
	half4 tangent	: TEXCOORD6;    // xyz: tangent, w: viewDir.y
	half4 bitangent : TEXCOORD7;    // xyz: binormal, w: viewDir.z

	UNITY_FOG_COORDS(9)

	UNITY_VERTEX_INPUT_INSTANCE_ID
	UNITY_VERTEX_OUTPUT_STEREO
};


struct GlobalData 
{
	float depth;		// Remapped Depth
	float sceneDepth;	// Linear Depth
	float rawDepthDst;	// Raw Depth Distorted
	float pixelDepth;
	float foamMask;
	float2 refractionOffset;
	float2 refractionUV;
	float4 finalColor;
	float4 refractionData;	// RGB: Refraction Color A: Refraction Depth
	float3 clearColor;		// RGB: Clear Color
	float3 shadowColor;
	float3 worldPosition;
	float3 worldNormal;
	float3 worldViewDir;
	float4 screenUV;

	float3 scattering;

	Light mainLight;
	float3 addLight;
	real3x3 tangentToWorld;
};

void InitializeGlobalData(inout GlobalData data, Varyings IN)
{
	data.depth = 0;
	data.sceneDepth = 0;
	data.rawDepthDst = 0;
	data.pixelDepth = IN.screenCoord.z;
	data.foamMask = 0;
	data.refractionOffset = float2(0, 0);
	data.refractionUV = float2(0, 0);
	data.refractionData = float4(0, 0, 0 ,0);
	data.clearColor = float3(1, 1, 1);
	data.finalColor = float4(1, 1, 1, 1);
	data.shadowColor = float3(1, 1, 1);
	data.worldPosition = float3(IN.normal.w, IN.tangent.w, IN.bitangent.w);
	data.worldNormal = float3(0, 1, 0);
	data.worldViewDir = GetWorldSpaceNormalizeViewDir(data.worldPosition); //SafeNormalize(_WorldSpaceCameraPos.xyz - data.worldPosition);
	data.screenUV = float4(IN.screenCoord.xyz / IN.screenCoord.w, IN.pos.z); //ComputeScreenPos(TransformWorldToHClip(data.worldPosition), _ProjectionParams.x);

	data.scattering = float3(0,0,0);

	data.mainLight = GetMainLight(TransformWorldToShadowCoord(data.worldPosition));
	data.addLight = float3(0, 0, 0);
	data.tangentToWorld = float3x3(IN.tangent.xyz, IN.bitangent.xyz, IN.normal.xyz);
}
