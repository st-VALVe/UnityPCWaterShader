using UnityEngine;
using System;
using UnityEngine.Rendering.Universal;
using UnityEngine.Rendering;
using UnityEngine.Experimental.Rendering;

namespace URPWater
{
    [ExecuteAlways]
    public class WaterReflection : MonoBehaviour
    {
        [SerializeField]
        private float _ClipPlaneOffset = 0.07f;
        [SerializeField]
        private LayerMask _LayerMask = -1;
        [SerializeField]

        public GameObject target;

        private static Camera _ReflectionCamera;
        private RenderTexture _ReflectionTexture;
        private readonly int _ReflectionTextureId = Shader.PropertyToID("_ReflectionTexture");

        public static event Action<ScriptableRenderContext, Camera> BeginReflections;


        private void OnEnable()
        {
            RenderPipelineManager.beginCameraRendering += ComputeReflections;
        }

        // Cleanup all the objects we possibly have created
        private void OnDisable()
        {
            Cleanup();
        }

        private void OnDestroy()
        {
            Cleanup();
        }

        private void ComputeReflections(ScriptableRenderContext context, Camera camera)
        {
            // we dont want to render planar reflections in reflections or previews
            if (camera.cameraType == CameraType.Reflection || camera.cameraType == CameraType.Preview)
                return;

            UpdateReflectionCamera(camera); // create reflected camera
            PlanarReflectionTexture(camera); // create and assign RenderTexture

            var data = new ReflectionSettingData(); // save quality settings and lower them for the planar reflections
            data.Set(); // set quality settings

            BeginReflections?.Invoke(context, _ReflectionCamera); // callback Action for PlanarReflection
            UniversalRenderPipeline.RenderSingleCamera(context, _ReflectionCamera); // render planar reflections

            data.Restore(); // restore the quality settings
            Shader.SetGlobalTexture(_ReflectionTextureId, _ReflectionTexture); // Assign texture to water shader
        }

        private void UpdateCamera(Camera src, Camera dest)
        {
            if (dest == null) return;

            dest.CopyFrom(src);
            dest.useOcclusionCulling = false;
            if (dest.gameObject.TryGetComponent(out UniversalAdditionalCameraData camData))
            {
                camData.renderShadows = false; // turn off shadows for the reflection camera
            }
        }

        private void UpdateReflectionCamera(Camera realCamera)
        {
            if (_ReflectionCamera == null)
                _ReflectionCamera = CreateReflectionCamera();

            // find out the reflection plane: position and normal in world space
            Vector3 pos = transform.position;
            Vector3 normal = Vector3.up;
            if (target != null)
            {
                pos = target.transform.position;
                normal = target.transform.up;
            }

            UpdateCamera(realCamera, _ReflectionCamera);

            // Render reflection
            // Reflect camera around reflection plane
            var d = -Vector3.Dot(normal, pos) - _ClipPlaneOffset;
            var reflectionPlane = new Vector4(normal.x, normal.y, normal.z, d);

            var reflection = Matrix4x4.identity;
            reflection *= Matrix4x4.Scale(new Vector3(1, -1, 1));

            ReflectionMatrix(ref reflection, reflectionPlane);
            var oldPosition = realCamera.transform.position - new Vector3(0, pos.y * 2, 0);
            var newPosition = ReflectPosition(oldPosition);
            _ReflectionCamera.transform.forward = Vector3.Scale(realCamera.transform.forward, new Vector3(1, -1, 1));
            _ReflectionCamera.worldToCameraMatrix = realCamera.worldToCameraMatrix * reflection;

            // Setup oblique projection matrix so that near plane is our reflection
            // plane. This way we clip everything below/above it for free.
            var clipPlane = CameraSpacePlane(_ReflectionCamera, pos - Vector3.up * 0.1f, normal, 1.0f);
            var projection = realCamera.CalculateObliqueMatrix(clipPlane);
            _ReflectionCamera.projectionMatrix = projection;
            _ReflectionCamera.cullingMask = _LayerMask & ~(1 << LayerMask.NameToLayer("Water"));// never render water layer
            _ReflectionCamera.transform.position = newPosition;
        }

        private void Cleanup()
        {
            RenderPipelineManager.beginCameraRendering -= ComputeReflections;

            if (_ReflectionCamera)
            {
                _ReflectionCamera.targetTexture = null;
                SafeDestroy(_ReflectionCamera.gameObject);
            }
            if (_ReflectionTexture)
            {
                RenderTexture.ReleaseTemporary(_ReflectionTexture);
            }
        }

        private static void SafeDestroy(UnityEngine.Object obj)
        {
            if (Application.isEditor)
            {
                DestroyImmediate(obj);
            }
            else
            {
                Destroy(obj);
            }
        }

        private void PlanarReflectionTexture(Camera cam)
        {
            if (_ReflectionTexture == null)
            {
                var res = ReflectionResolution(cam, UniversalRenderPipeline.asset.renderScale);
                const bool useHdr10 = true;
                const RenderTextureFormat hdrFormat = useHdr10 ? RenderTextureFormat.RGB111110Float : RenderTextureFormat.DefaultHDR;
                _ReflectionTexture = RenderTexture.GetTemporary((int)res.x, (int)res.y, 16,
                    GraphicsFormatUtility.GetGraphicsFormat(hdrFormat, true));
                _ReflectionTexture.useMipMap = true;
                _ReflectionTexture.autoGenerateMips = true;
            }

            _ReflectionCamera.targetTexture = _ReflectionTexture;
        }

        private Vector2 ReflectionResolution(Camera cam, float scale)
        {
            var x = (int)(cam.pixelWidth * scale * 0.5f);
            var y = (int)(cam.pixelHeight * scale * 0.5f);
            return new Vector2(x, y);
        }

        private Camera CreateReflectionCamera()
        {
            var go = new GameObject("Reflection Camera", typeof(Camera));
            var cameraData = go.AddComponent(typeof(UniversalAdditionalCameraData)) as UniversalAdditionalCameraData;

            cameraData.requiresColorOption = CameraOverrideOption.Off;
            cameraData.requiresDepthOption = CameraOverrideOption.Off;
            cameraData.SetRenderer(0);

            var t = transform;
            var reflectionCamera = go.GetComponent<Camera>();
            reflectionCamera.transform.SetPositionAndRotation(t.position, t.rotation);
            reflectionCamera.depth = -10;
            reflectionCamera.enabled = false;

            go.hideFlags = HideFlags.HideAndDontSave;

            return reflectionCamera;
        }

        // Calculates reflection matrix around the given plane
        private static void ReflectionMatrix(ref Matrix4x4 reflectionMat, Vector4 plane)
        {
            reflectionMat.m00 = (1F - 2F * plane[0] * plane[0]);
            reflectionMat.m01 = (-2F * plane[0] * plane[1]);
            reflectionMat.m02 = (-2F * plane[0] * plane[2]);
            reflectionMat.m03 = (-2F * plane[3] * plane[0]);

            reflectionMat.m10 = (-2F * plane[1] * plane[0]);
            reflectionMat.m11 = (1F - 2F * plane[1] * plane[1]);
            reflectionMat.m12 = (-2F * plane[1] * plane[2]);
            reflectionMat.m13 = (-2F * plane[3] * plane[1]);

            reflectionMat.m20 = (-2F * plane[2] * plane[0]);
            reflectionMat.m21 = (-2F * plane[2] * plane[1]);
            reflectionMat.m22 = (1F - 2F * plane[2] * plane[2]);
            reflectionMat.m23 = (-2F * plane[3] * plane[2]);

            reflectionMat.m30 = 0F;
            reflectionMat.m31 = 0F;
            reflectionMat.m32 = 0F;
            reflectionMat.m33 = 1F;
        }

        // Given position/normal of the plane, calculates plane in camera space.
        private Vector4 CameraSpacePlane(Camera cam, Vector3 pos, Vector3 normal, float sideSign)
        {
            var offsetPos = pos + normal * _ClipPlaneOffset;
            var m = cam.worldToCameraMatrix;
            var cameraPosition = m.MultiplyPoint(offsetPos);
            var cameraNormal = m.MultiplyVector(normal).normalized * sideSign;
            return new Vector4(cameraNormal.x, cameraNormal.y, cameraNormal.z, -Vector3.Dot(cameraPosition, cameraNormal));
        }

        private static Vector3 ReflectPosition(Vector3 pos)
        {
            var newPos = new Vector3(pos.x, -pos.y, pos.z);
            return newPos;
        }

        class ReflectionSettingData
        {
            private readonly bool _Fog;

            public ReflectionSettingData()
            {
                _Fog = RenderSettings.fog;
            }

            public void Set()
            {
                GL.invertCulling = true;
                RenderSettings.fog = false; // disable fog for now as it's incorrect with projection
            }

            public void Restore()
            {
                GL.invertCulling = false;
                RenderSettings.fog = _Fog;
            }
        }

    }
}