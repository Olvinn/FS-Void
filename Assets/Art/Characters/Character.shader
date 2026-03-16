Shader "Custom/Character"
{
    Properties
    {
        [MainColor] _BaseColor("Base Color", Color) = (1, 1, 1, 1)
        [MainColor] _RColor("R Color", Color) = (1, 1, 1, 1)
        [MainColor] _GColor("G Color", Color) = (1, 1, 1, 1)
        [MainColor] _BColor("B Color", Color) = (1, 1, 1, 1)
        [MainTexture] _BaseMap("Base Map", 2D) = "white"
    }

    SubShader
    {
        Tags { "RenderType" = "Opaque" "RenderPipeline" = "UniversalPipeline" }

        Pass
        {
            HLSLPROGRAM

            #pragma vertex vert
            #pragma fragment frag

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"

            struct Attributes
            {
                float4 positionOS : POSITION;
                float2 uv : TEXCOORD0;
                float3 normalOS : NORMAL;
            };

            struct Varyings
            {
                float4 positionHCS : SV_POSITION;
                float2 uv : TEXCOORD0;
                float3 normalOS : TEXCOORD1;
                float3 positionWS : TEXCOORD2;
            };

            TEXTURE2D(_BaseMap);
            SAMPLER(sampler_BaseMap);

            CBUFFER_START(UnityPerMaterial)
                half4 _BaseColor;
                half4 _RColor;
                half4 _GColor;
                half4 _BColor;
                float4 _BaseMap_ST;
            CBUFFER_END

            Varyings vert(Attributes IN)
            {
                Varyings OUT;
                OUT.positionHCS = TransformObjectToHClip(IN.positionOS.xyz);
                OUT.positionWS = TransformObjectToWorld(IN.positionOS.xyz);
                OUT.uv = TRANSFORM_TEX(IN.uv, _BaseMap);
                //OUT.normalWS = TransformObjectToWorldNormal(IN.normalOS);
                OUT.normalOS = IN.normalOS;
                return OUT;
            }
            
            half3 BlinnPhongSpecular(half3 normal, half3 lightDir, half3 viewDir, half3 specColor, half shininess)
            {
                half3 H = normalize(lightDir + viewDir);
                half NdotH = saturate(dot(normal, H));
                half spec = pow(NdotH, shininess);
                return specColor * spec;
            }

            half4 frag(Varyings IN) : SV_Target
            {
                half3 normalWS = TransformObjectToWorldNormal(IN.normalOS);
                
                half4 mask = SAMPLE_TEXTURE2D(_BaseMap, sampler_BaseMap, IN.uv);
                half4 light = saturate(_BaseColor + _RColor * mask.r + _GColor * mask.g + _BColor * mask.b);
                
                half3 ambientColor = SampleSH(normalWS);
                half4 dark = half4(saturate(light * ambientColor), light.a);
                
                Light mainLight = GetMainLight();
                half3 viewDir = normalize(GetCameraPositionWS() - IN.positionWS);
                half4 color = lerp(dark, light, floor(dot(normalize(mainLight.direction), normalWS) * .5 + 1));
                
                color.rgb += BlinnPhongSpecular(normalWS, mainLight.direction, viewDir, mainLight.color, 100) * color.a;
                
                return color;
            }
            ENDHLSL
        }
    }
}
