// ShadowCoord: TransformWorldToShadowCoord(worldPosition);
// WorldNormal: TransformObjectToWorldNormal(v.normal);
// worldViewDir: SafeNormalize(_WorldSpaceCameraPos.xyz - worldPos)
// worldPos: TransformObjectToWorld(v.vertex.xyz);
// ShadowCoord: TransformWorldToShadowCoord(WorldPos);

void ComputeCaustics(out float3 causticColor, inout GlobalData data, Varyings IN, float3 Ambient)
{
	#if UNITY_REVERSED_Z
		real depth = data.rawDepthDst;
	#else
		// Adjust Z to match NDC for OpenGL ([-1, 1])
		real depth = lerp(UNITY_NEAR_CLIP_VALUE, 1, data.rawDepthDst);
	#endif

	float3 worldUV = ComputeWorldSpacePosition(data.refractionUV, depth, UNITY_MATRIX_I_VP);

	float causticFade = DistanceFade(data.refractionData.a, data.pixelDepth, _CausticsStart, _CausticsEnd);

	float4 offsets = frac(_CausticsSpeed * _Time.x);
	float3 CausticsA = SAMPLE_TEXTURE2D(_CausticsTex, Linear_repeat_sampler, worldUV.xz * _CausticsTiling.xy + offsets.xy).rgb;
	float3 CausticsB = SAMPLE_TEXTURE2D(_CausticsTex, Linear_repeat_sampler, worldUV.xz * _CausticsTiling.zw + offsets.zw).rgb;
	float3 CausticMix = min(CausticsA, CausticsB);

	// Caustic projection for shadow
	Light mainLight = GetMainLight(TransformWorldToShadowCoord(worldUV));
	float shadow = mainLight.shadowAttenuation;

	causticFade *= 1 - data.foamMask * 2;

	causticColor = CausticMix * max(0,_CausticsIntensity) * causticFade * (shadow + Ambient * 0.5);

}

// =================================================================
// Directional light computations
// =================================================================
float3 ComputeMainLightDiffuse(float3 direction, float3 worldNormal)
{
	return saturate(dot(worldNormal, direction));
}

float3 ComputeMainLightSpecular(
	Light mainLight,
	float3 worldNormal,
	float3 worldViewDir,
	float3 specular,
	float smoothness)
{
	smoothness = exp2(10 * smoothness + 1);
	
	// Unity spec
	return LightingSpecular(mainLight.color, mainLight.direction, worldNormal, worldViewDir, float4(specular, 0), smoothness);
}

Light ComputeMainLight(float3 worldPos)
{
	return GetMainLight(TransformWorldToShadowCoord(worldPos));
}

void ComputeUnderWaterShading(inout GlobalData data, Varyings IN, float3 ambient) 
{
	float3 clearRefraction = data.refractionData.rgb;

	float3 shallowColor = _Color.rgb * data.refractionData.rgb;
	float3 depthColor = _DepthColor.rgb * data.shadowColor.rgb;
	data.refractionData.rgb = lerp(depthColor, shallowColor, data.depth);

	float invDepth = 1 - data.depth;
	data.finalColor.rgb = lerp(data.refractionData.rgb, data.refractionData.rgb * saturate(data.mainLight.color) , invDepth);
}

void ComputeLighting(inout GlobalData data, Varyings IN)
{
	Light mainLight = data.mainLight;

	float3 lightDir = mainLight.direction;
	float3 lightColor = mainLight.color;

	float3 mainSpecular = ComputeMainLightSpecular(mainLight, data.worldNormal, data.worldViewDir, 1, _Smoothness);
	
	float shadow = mainLight.shadowAttenuation;
	float shadowMask = shadow;//max(data.depth, shadow);
	float3 ambient = SampleSH(data.worldNormal);
		
	// Shadow
	data.shadowColor = lerp(saturate(ambient * 2), float3(1, 1, 1), shadowMask);

	// Underwater color
	ComputeUnderWaterShading(data, IN, ambient);

	float3 caustics = float3(1,1,1);
	ComputeCaustics(caustics, data, IN, ambient);

	data.finalColor.rgb += data.finalColor.rgb * caustics * saturate(length(lightColor));

	data.finalColor.rgb += data.scattering * shadow;

	mainSpecular *= 1- saturate(data.foamMask.xxx);

	float3 foamColor = _FoamColor.rgb * (lightColor + ambient) * (shadow + ambient);
	data.finalColor.rgb = lerp(data.finalColor.rgb, foamColor, data.foamMask * _FoamColor.a);

	// Specular and additive light after reflection
	data.addLight = mainSpecular * data.shadowColor; 
	// Shadows
	data.finalColor.rgb = data.finalColor.rgb * data.shadowColor;
}