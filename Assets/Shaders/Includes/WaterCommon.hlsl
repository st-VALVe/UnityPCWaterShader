struct WaveData
{
	float4 wave;
	float speed;
};

float3 GerstnerWave(WaveData data, float3 p, inout float3 tangent, inout float3 binormal)
{
	float speed = _Time.y * data.speed;
	float steepness = data.wave.z * 0.1;
	float wavelength = data.wave.w;
	float k = 6.28318 / wavelength; // 2 * PI
	float c = sqrt(9.8 / k);
	float2 d = normalize(data.wave.xy);
	float f = k * (dot(d, p.xz) - c * speed);
	float a = steepness / k;
	float sinF = sin(f);
	float cosF = cos(f);
	float sinSteepness = steepness * sinF;
	float cosSteepness = steepness * cosF;

	tangent += float3(
		-d.x * d.x * sinSteepness,
		d.x * cosSteepness,
		-d.x * d.y * sinSteepness
		);
	binormal += float3(
		-d.x * d.y * sinSteepness,
		d.y * cosSteepness,
		-d.y * d.y * sinSteepness
		);
	return float3(
		d.x * (a * cosF),
		a * sinF,
		d.y * (a * cosF)
		);
}


void ComputeWaves(inout Attributes v)
{
	float3 gridPoint = TransformObjectToWorld(v.vertex.xyz);
	float3 tangent = float3(1, 0, 0);
	float3 binormal = float3(0, 0, 1);
	float3 p = gridPoint;

	WaveData waveData;
	waveData.wave = _GerstnerWave;
	waveData.speed = _GerstnerSpeed;

	p += GerstnerWave(waveData, gridPoint, tangent, binormal);

	float3 normal = normalize(cross(binormal, tangent));

	p = TransformWorldToObject(p);

	float fakeOffset = p.y - v.vertex.y;

	v.waveHeight = fakeOffset * 0.5 + 0.5;
	v.vertex.xyz = p;
	v.normal = normal;
}

float3 UnpackScaleNormal(float4 packednormal) {
#if defined(UNITY_NO_DXT5nm)
	return packednormal.xyz * 2 - 1;
#else
	half3 normal;
	normal.xy = (packednormal.wy * 2 - 1);
	normal.z = sqrt(1.0 - saturate(dot(normal.xy, normal.xy)));
	return normal;
#endif
}

float3 BlendNormals(float3 n1, float3 n2)
{
	return normalize(half3(n1.xy + n2.xy, n1.z * n2.z));
}

float3 NormalBlendReoriented(float3 A, float3 B)
{
	float3 t = A.xyz + float3(0.0, 0.0, 1.0);
	float3 u = B.xyz * float3(-1.0, -1.0, 1.0);
	return (t / t.z) * dot(t, u) - u;
}

void ComputeNormals(inout GlobalData data, Varyings IN)
{
	float3 tangentNormal;

	float4 nA = SAMPLE_TEXTURE2D(_NormalMap, Trilinear_repeat_sampler, IN.texcoord.xy);
	float4 nB = SAMPLE_TEXTURE2D(_NormalMap, Trilinear_repeat_sampler, IN.texcoord.zw);

	float3 normalA = UnpackScaleNormal(nA);
	float3 normalB = UnpackScaleNormal(nB);

	tangentNormal = NormalBlendReoriented(normalA, normalB);

	// Combined tangent to world
	float3 normalWS = TransformTangentToWorld(tangentNormal, data.tangentToWorld);
	data.worldNormal = normalize(normalWS);
}

float3 SampleReflections(float3 worldNormal, float3 worldViewDir, float2 screenUV)
{
	float3 reflection = 0;
	float2 refOffset = 0;

	float3 reflectVector = reflect(-worldViewDir, worldNormal);

	float2 reflectionUV = screenUV + worldNormal.zx * float2(0.02, 0.15);

	//planar reflection
	reflection = SAMPLE_TEXTURE2D_LOD(_ReflectionTexture, sampler_ScreenTextures_linear_clamp, reflectionUV, 6 * _ReflectionRoughness).rgb;

	return reflection;
}

void ComputeReflections(inout GlobalData data, Varyings IN)
{
	// Reflection Distortion
	float3 reflectionNormal = data.worldNormal;
	float3 n = IN.worldNormal;
	n.xz *= _ReflectionDistortion * 10;
	reflectionNormal = lerp(n, reflectionNormal, _ReflectionDistortion);

	float fresnelFade = _ReflectionFresnelNormal;

	float3 fresnelNormal = lerp(IN.worldNormal, data.worldNormal, fresnelFade);
	float fresnel = 1 - dot(fresnelNormal, data.worldViewDir);
	fresnel = pow(saturate(fresnel), _ReflectionFresnel);

	float3 reflection = SampleReflections(reflectionNormal, data.worldViewDir, data.screenUV.xy);

	float reflectionMask = _ReflectionIntensity;

	reflectionMask *= 1 - data.foamMask * 2;

	float3 finalReflection = lerp(data.finalColor.rgb, saturate(reflection), fresnel * saturate(reflectionMask));

	data.finalColor.rgb = finalReflection;
	data.finalColor.rgb += data.addLight;
}

void ComputeOpaqueAndDepth(inout GlobalData data, out float4 clearData, out float4 refractionData, out float2 refractionOffset)
{
	float2 screenUV = data.screenUV.xy;

	//UNITY_SAMPLE_SCREENSPACE_TEXTURE(_CameraOpaqueTexture, sampler_CameraOpaqueTexture_linear_clamp, screenUV);
	clearData.rgb = SampleSceneColor(screenUV); // Color
	clearData.a = SampleDepth(screenUV); // Depth

	// Distorted Data
	float2 distortionAmount = _CameraOpaqueTexture_TexelSize.xy * _Distortion.xx;

	// Far Distortion
	float farDistance = saturate(1 - length(data.worldPosition.rgb - _WorldSpaceCameraPos.xyz) / 50);
	distortionAmount = lerp(distortionAmount * 0.25, distortionAmount, farDistance);

	float2 offset = data.worldNormal.xz * distortionAmount;
	float2 GrabUV = OffsetUV(data.screenUV, offset);
	float2 DepthUV = OffsetDepth(data.screenUV, offset);

	float4 distortedData;
	//UNITY_SAMPLE_SCREENSPACE_TEXTURE(_CameraOpaqueTexture, sampler_CameraOpaqueTexture_linear_clamp, GrabUV);

	float rawDepth = SampleRawDepth(DepthUV);

	distortedData.rgb = SampleSceneColor(GrabUV); // Color
	distortedData.a = RawDepthToLinear(rawDepth);//SampleDepth(DepthUV); // Depth

	refractionData = data.pixelDepth > distortedData.a ? clearData : distortedData;
	refractionOffset = offset;

	data.refractionUV = DepthUV;
	data.rawDepthDst = rawDepth;
}

void ComputeRefractionData(inout GlobalData data)
{
	float4 clearData;
	float4 refractionData;
	float2 refractionOffset;
	float rawDepth;
	float3 subNormal;

	ComputeOpaqueAndDepth(data, clearData, refractionData, refractionOffset);
	data.depth = DistanceFade(refractionData.a, data.pixelDepth, _DepthStart, _DepthEnd);

	// Compositing in lighting
	data.refractionData = refractionData;
	data.clearColor.rgb = clearData.rgb;
	data.sceneDepth = clearData.a;
	data.refractionOffset = refractionOffset;
}

void ComputeScattering(inout GlobalData data, Varyings IN)
{	
		Light mainLight = data.mainLight;

		float3 lightColor = mainLight.color;

		float3 L = mainLight.direction;
		float3 V = data.worldViewDir;
		float3 N = IN.worldNormal;

		float3 H = normalize(L + N * _ScatteringRangeMin);
		float VdotH = pow(saturate(max(0, dot(V, -H))), _ScatteringRangeMax);
		
		float scatterMask = saturate(VdotH) * _ScatteringIntensity;
		
		float3 scatterColor = _ScatteringColor.rgb * saturate(scatterMask);

		data.scattering = scatterColor * saturate(lightColor);
}

void ComputeFoam(inout GlobalData data, Varyings IN)
{
	float2 foamDistortion = data.worldNormal.xz * _FoamDistortion;

	float edgeMask = DistanceFade(data.sceneDepth, data.pixelDepth, 0, max(0, _FoamSize));
	float foamTex = SAMPLE_TEXTURE2D(_FoamTex, Trilinear_repeat_sampler, IN.texcoord1.zw + foamDistortion).r;

	data.foamMask = foamTex * edgeMask;
}

void ComputeAlpha(inout GlobalData data, Varyings IN)
{
	float mask = 1;

	float edgeMask = 1 - DistanceFade(data.sceneDepth, data.pixelDepth, 0, max(0, _EdgeSize));
	mask *= edgeMask;

	data.finalColor.rgb = lerp(data.clearColor.rgb, data.finalColor.rgb, mask);
	data.finalColor.a = mask;
}



Varyings vert(Attributes v)
{
	Varyings OUT;

	UNITY_SETUP_INSTANCE_ID(v);
	UNITY_TRANSFER_INSTANCE_ID(v, OUT);
	UNITY_INITIALIZE_VERTEX_OUTPUT_STEREO(OUT);

	ComputeWaves(v);

	float3 worldPos = TransformObjectToWorld(v.vertex.xyz);

	v.texcoord.xy = worldPos.xz * 0.1;

	OUT.pos = TransformObjectToHClip(v.vertex.xyz);
	OUT.color = v.color;

	VertexNormalInputs vertexTBN = GetVertexNormalInputs(v.normal, v.tangent);

	OUT.normal = float4(vertexTBN.normalWS, worldPos.x);
	OUT.tangent = float4(vertexTBN.tangentWS, worldPos.y);
	OUT.bitangent = float4(vertexTBN.bitangentWS, worldPos.z);

	OUT.worldNormal = OUT.normal.xyz;
	OUT.screenCoord = ComputeScreenPos(OUT.pos);
	OUT.screenCoord.z = ComputePixelDepth(worldPos); // ComputeEyeDepth

	OUT.texcoord = DualAnimatedUV(v.texcoord, _NormalMapTilings, _NormalMapSpeeds);

	OUT.texcoord1 = float4(0, 0, 0, 0);
	OUT.texcoord3 = float4(0, 0, 0, 0);
	OUT.texcoord3.x = saturate(OUT.screenCoord.z);

	OUT.texcoord3.y = v.waveHeight;

	OUT.texcoord1.zw = v.texcoord.xy * _FoamTiling.xy;

	UNITY_TRANSFER_FOG(OUT, OUT.pos);

	return OUT;
}

FRONT_FACE_TYPE vFace : FRONT_FACE_SEMANTIC;

float4 frag(Varyings IN) : SV_Target
{
	UNITY_SETUP_INSTANCE_ID(IN);

	GlobalData data;
	InitializeGlobalData(data, IN);

	ComputeNormals(data, IN);
	ComputeRefractionData(data);
	ComputeScattering(data, IN);
	ComputeFoam(data, IN);
	ComputeLighting(data, IN);
	ComputeReflections(data, IN);

	UNITY_APPLY_FOG(IN.fogCoord, data.finalColor);

	ComputeAlpha(data, IN);

	float4 output;
	output.rgb = data.finalColor.rgb;
	output.a = data.finalColor.a;

	return output;
}