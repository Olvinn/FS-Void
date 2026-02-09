Shader "Custom/Stars"
{
    Properties
    {
        _StarsDensity ("Stars Density", Range(1, 1000)) = 400
        _StarsDistribution ("Stars Distribution", Range(.9, .99999)) = 1
        _MainStarSize ("Main Star Size", Range(0, 180)) = 1
        _GalaxyDepth ("Galaxy Depth", Range(1, 10)) = .1
        _GalaxyIntensity ("Galaxy Intensity", Range(0, 10)) = .1
    }

    SubShader
    {
        Tags
        {
            "Queue"="Background"
            "RenderType"="Background"
            "PreviewType"="Skybox"
        }

        Cull Off
        ZWrite Off
        ZTest Less

        Pass
        {
            HLSLPROGRAM

            #pragma vertex vert
            #pragma fragment frag

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"

            struct Attributes
            {
                float4 positionOS : POSITION;
                float2 uv : TEXCOORD0;
            };

            struct Varyings
            {
                float4 positionHCS : SV_POSITION;
                float3 viewDirWS   : TEXCOORD0;
            };

            CBUFFER_START(UnityPerMaterial)
            half _StarsDensity;
            half _StarsDistribution;
            half _MainStarSize;
            half _GalaxyDepth;
            half _GalaxyIntensity;
            CBUFFER_END

            Varyings vert(Attributes IN)
            {
                Varyings OUT;
                OUT.positionHCS = TransformObjectToHClip(IN.positionOS.xyz);
                float3 worldPos = TransformObjectToWorld(IN.positionOS.xyz);
                OUT.viewDirWS = normalize(worldPos - _WorldSpaceCameraPos);
                return OUT;
            }
            
            float hash31(float3 p)
            {
                p = frac(p * 0.1031);
                p += dot(p, p.yzx + 33.33);
                return frac((p.x + p.y) * p.z);
            }

            half4 frag(Varyings IN) : SV_Target
            {
                float3 d = normalize(IN.viewDirWS);
                
                half4 color = 0;
                half4 galaxy = saturate(pow(1 - abs(dot(d, half3(0, 1, 0))), _GalaxyDepth));
                color = galaxy * _GalaxyIntensity;
                
                float3 cell = floor(d * _StarsDensity);
                float rnd = hash31(cell);
                float star = step(_StarsDistribution * Remap(0, 1, .9, 1, 1 - galaxy), rnd); 
                
                half4 stars = half4(star, star, star, 1);
                stars *= hash31(d) * 2;
                color += stars;
                
                float3 lightDir = _MainLightPosition;
                half size = cos(DegToRad(_MainStarSize));
                half4 mainStar = dot(d, lightDir) > size ? _MainLightColor : 0;
                color += mainStar;
                

                return color;
            }
            ENDHLSL
        }
    }
}
