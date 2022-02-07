//  Fog helpers
//
//  multi_compile_fog Will compile fog variants.
//  UNITY_FOG_COORDS(texcoordindex) Declares the fog data interpolator.
//  UNITY_TRANSFER_FOG(outputStruct,clipspacePos) Outputs fog data from the vertex shader.
//  UNITY_APPLY_FOG(fogData,col) Applies fog to color "col". Automatically applies black fog when in forward-additive pass.
//  Can also use UNITY_APPLY_FOG_COLOR to supply your own fog color.

// In case someone by accident tries to compile fog code in one of the g-buffer or shadow passes:
// treat it as fog is off.
#if defined(UNITY_PASS_PREPASSBASE) || defined(UNITY_PASS_DEFERRED) || defined(UNITY_PASS_SHADOWCASTER)
#undef FOG_LINEAR
#endif

#if defined(FOG_LINEAR)
	// factor = (end-z)/(end-start) = z * (-1/(end-start)) + (end/(end-start))
	#define UNITY_CALC_FOG_FACTOR_RAW(coord) float unityFogFactor = (coord) * unity_FogParams.z + unity_FogParams.w	
#endif

#define UNITY_CALC_FOG_FACTOR(coord) UNITY_CALC_FOG_FACTOR_RAW(UNITY_Z_0_FAR_FROM_CLIPSPACE(coord))

#define UNITY_FOG_COORDS_PACKED(idx, vectype) vectype fogCoord : TEXCOORD##idx;

#define UNITY_FOG_COORDS(idx) UNITY_FOG_COORDS_PACKED(idx, float1)
// SM3.0 and PC/console: calculate fog distance per-vertex, and fog factor per-pixel
#define UNITY_TRANSFER_FOG(o,outpos) o.fogCoord.x = (outpos).z

#define UNITY_FOG_LERP_COLOR(col,fogCol,fogFac) col.rgb = lerp((fogCol).rgb, (col).rgb, saturate(fogFac))

#if defined(FOG_LINEAR) || defined(FOG_EXP) || defined(FOG_EXP2)		
	// SM3.0 and PC/console: calculate fog factor and lerp fog color
	#define UNITY_APPLY_FOG_COLOR(coord,col,fogCol) UNITY_CALC_FOG_FACTOR((coord).x); UNITY_FOG_LERP_COLOR(col,fogCol,unityFogFactor)
	#define UNITY_EXTRACT_FOG(name) float _unity_fogCoord = name.fogCoord
#else
	#define UNITY_APPLY_FOG_COLOR(coord,col,fogCol)
	#define UNITY_EXTRACT_FOG(name)
#endif

#define UNITY_APPLY_FOG(coord,col) UNITY_APPLY_FOG_COLOR(coord,col,unity_FogColor)