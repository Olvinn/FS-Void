Shader "Custom/Character"
{
    Properties
    {
        [MainColor] _BaseColor("Base Color", Color) = (1, 1, 1, 1)
        _RColor("R Color", Color) = (1, 1, 1, 1)
        _GColor("G Color", Color) = (1, 1, 1, 1)
        _BColor("B Color", Color) = (1, 1, 1, 1)
        _Roughness("Roughness", Range(0,1)) = .5
        _Metallic("Metallic", Range(0,1)) = .5
        _OutlineThickness("Outline Thickness", Float) = 10
        _OutlineColor("Outline Color", Color) = (1,1,1,1)
        [MainTexture] _BaseMap("Base Map", 2D) = "white"
        [Toggle] _Blend("Blend", Int) = 1
        [Toggle] _Specular("Specular", Int) = 1
        [Toggle] _Aniso("Anisotropic", Int) = 1
    }

    SubShader
    {
        Pass
        {
            Name "CellShading"
            Tags { "RenderType" = "Opaque" "RenderPipeline" = "UniversalForward" }
            Cull Back
            
            HLSLPROGRAM
            
            #pragma vertex vert
            #pragma fragment frag

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Shadows.hlsl"
            
            #pragma multi_compile _ _MAIN_LIGHT_SHADOWS _MAIN_LIGHT_SHADOWS_CASCADE _MAIN_LIGHT_SHADOWS_SCREEN
            #pragma multi_compile _ _ADDITIONAL_LIGHT_SHADOWS
            #pragma multi_compile _ _SHADOWS_SOFT
            
            struct Attributes
            {
                float4 positionOS : POSITION;
                float2 uv         : TEXCOORD0;
                float3 normalOS   : NORMAL;
                float4 tangentOS  : TANGENT;
            };

            struct Varyings
            {
                float4 positionHCS : SV_POSITION;
                float2 uv          : TEXCOORD0;
                float3 normalWS    : TEXCOORD1;
                float3 tangentWS   : TEXCOORD2;
                float3 bitangentWS : TEXCOORD3;
                float3 positionWS  : TEXCOORD4;
            };

            TEXTURE2D(_BaseMap); SAMPLER(sampler_BaseMap);

            CBUFFER_START(UnityPerMaterial)
                half4 _BaseColor;
                half4 _RColor;
                half4 _GColor;
                half4 _BColor;
                float4 _BaseMap_ST;
                int _Blend, _Specular, _Aniso;
                half _Roughness, _Metallic;
            CBUFFER_END
            
            float AnisotropicGGX_D(float3 N, float3 H, float3 T, float3 B, float roughX, float roughY)
            {
                float TdotH = dot(T, H);
                float BdotH = dot(B, H);
                float NdotH = dot(N, H);

                float a2 = roughX * roughY;

                float v = (TdotH * TdotH) / (roughX * roughX)
                        + (BdotH * BdotH) / (roughY * roughY)
                        + NdotH * NdotH;

                return 1.0 / (PI * a2 * v * v);
            }

            float AnisotropicGGX_G1(float NdotV, float VdotT, float VdotB, float roughX, float roughY)
            {
                float a = sqrt(
                    (VdotT * roughX) * (VdotT * roughX) +
                    (VdotB * roughY) * (VdotB * roughY) +
                    NdotV * NdotV
                );
                return (2.0 * NdotV) / (NdotV + a);
            }

            half3 AnisotropicSpecular(
                float3 N,           // surface normal
                float3 T,           // tangent  (from mesh or bent for effect)
                float3 B,           // bitangent
                float3 V,           // view direction (toward camera)
                float3 L,           // light direction (toward light)
                float3 F0,          // fresnel base reflectance (e.g. 0.04 dielectric, albedo for metal)
                float  roughX,      // roughness along T (anisotropy axis)
                float  roughY       // roughness along B
            )
            {
                float3 H     = normalize(V + L);
                float  NdotL = saturate(dot(N, L));
                float  NdotV = saturate(dot(N, V));

                if (NdotL < 1e-5 || NdotV < 1e-5) return 0;

                float  D = AnisotropicGGX_D(N, H, T, B, roughX, roughY);

                float  G = AnisotropicGGX_G1(NdotV, dot(V,T), dot(V,B), roughX, roughY)
                         * AnisotropicGGX_G1(NdotL, dot(L,T), dot(L,B), roughX, roughY);

                float  HdotV = saturate(dot(H, V));
                float3 F     = F0 + (1.0 - F0) * pow(1.0 - HdotV, 5.0);

                return (D * G * F) / max(4.0 * NdotL * NdotV, .5);
            }
            
            half3 Specular(half3 normal, half3 tangent, half3 bitangent, half3 lightDir, half3 viewDir, half3 specColor, half3 color)
            {
                if (_Aniso)
                    return AnisotropicSpecular(normal, tangent, bitangent, viewDir, lightDir, lerp(0.04, color, _Metallic), .8, .1);
                else
                {
                    half3 H = normalize(lightDir + viewDir);
                    half NdotH = saturate(dot(normal, H));
                    half spec = pow(NdotH, 100 * _Metallic);
                    return specColor * spec * _Roughness;
                }
            }

            Varyings vert(Attributes IN)
            {
                Varyings OUT;
                OUT.positionHCS = TransformObjectToHClip(IN.positionOS.xyz);
                OUT.positionWS = TransformObjectToWorld(IN.positionOS.xyz);
                OUT.uv = TRANSFORM_TEX(IN.uv, _BaseMap);
                VertexNormalInputs normalInputs = GetVertexNormalInputs(IN.normalOS, IN.tangentOS);

                OUT.normalWS    = normalInputs.normalWS;
                OUT.tangentWS   = normalInputs.tangentWS;
                OUT.bitangentWS = normalInputs.bitangentWS;
                
                return OUT;
            }

            half4 frag(Varyings IN) : SV_Target
            {                
                half3 viewDir = normalize(GetCameraPositionWS() - IN.positionWS);
                
                float4 shadowCoord;
                #ifdef _MAIN_LIGHT_SHADOWS_SCREEN
                    shadowCoord = ComputeScreenPos(IN.positionHCS);
                #else
                    shadowCoord = TransformWorldToShadowCoord(IN.positionWS);
                #endif
                Light mainLight = GetMainLight(shadowCoord);
                
                half4 mask = SAMPLE_TEXTURE2D(_BaseMap, sampler_BaseMap, IN.uv);
                half4 light = lerp(_BaseColor, _RColor, max(mask.r, max(mask.g, mask.b)));
                light = lerp(light, _GColor, max(mask.g, mask.b));
                light = lerp(light, _BColor, mask.b);
                light.rgb *= mainLight.color;
                
                half3 ambientColor = SampleSH(IN.normalWS);
                half4 dark = half4(saturate(light * ambientColor), light.a);
                
                half rim = pow(saturate(1-dot(IN.normalWS, viewDir)), 20);
                //return half4(rim,rim,rim,1);
                
                half d = (dot(normalize(mainLight.direction), IN.normalWS) * .5 + .5) * mainLight.shadowAttenuation;
                half4 color = lerp(dark, light, floor(d + .5));
                half blend = .1;
                if (d > (.5 - blend * .5) && d < (.5 + blend * .5) && _Blend)
                    color = lerp(dark, light, saturate((d - (.5 - blend * .5)) / blend));
                
                if (_Specular)
                    color.rgb += Specular(IN.normalWS, IN.tangentWS, IN.bitangentWS, mainLight.direction, viewDir, mainLight.color, color.rgb) * .5;
                color.rgb += rim * ambientColor * .5;
                return color;
            }
            ENDHLSL
        }
        Pass
        {
            Name "Outline"
            Tags { "RenderType" = "Opaque" "LightMode" = "SRPDefaultUnlit" } 
            Cull Front
            
            HLSLPROGRAM
            
            #pragma vertex vert
            #pragma fragment frag

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            
            half _OutlineThickness;
            half4 _OutlineColor;
            
            struct Attributes
            {
                float4 positionOS : POSITION;
                float3 normalOS   : NORMAL;
            };

            struct Varyings
            {
                float4 positionHCS : SV_POSITION;
            };

            Varyings vert(Attributes IN)
            {
                Varyings OUT;
                float3 posWS  = TransformObjectToWorld(IN.positionOS.xyz + IN.normalOS * _OutlineThickness);

                float4 posCS    = TransformWorldToHClip(posWS);

                OUT.positionHCS  = posCS;
                return OUT;
            }

            half4 frag(Varyings IN) : SV_Target
            {                
               return _OutlineColor;
            }
            ENDHLSL
        }

        Pass
        {
            Name "ShadowCaster"
            Tags { "LightMode" = "ShadowCaster" }
        
            HLSLPROGRAM
            #pragma target 5.0
            #pragma vertex vert
            #pragma fragment frag

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Shadows.hlsl"

            struct Attributes
            {
                float4 vertex : POSITION;
            };

            struct Varyings
            {
                float4 positionCS   : SV_POSITION;
            };

            Varyings vert(Attributes IN)
            {
                Varyings OUT = (Varyings)0;
                OUT.positionCS = TransformObjectToHClip(IN.vertex);
                
                return OUT;
            }

            half4 frag(Varyings i) : SV_Target
            {                
                return 0;
            }
            ENDHLSL
        }
    }
}
