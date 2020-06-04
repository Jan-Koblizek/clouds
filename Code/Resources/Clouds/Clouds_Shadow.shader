Shader "Unlit/Clouds_Shadow"
{
    Properties
    {
        _MainTex ("Texture", 2D) = "white" {}
    }
	SubShader
	{
		Tags {"LightMode" = "ShadowCaster"}
		LOD 100
		CULL Front
		ZWrite On

		Pass
		{
			CGPROGRAM
			#pragma vertex vert
			#pragma fragment frag

			#include "UnityCG.cginc"

			struct appdata
			{
				float4 vertex : POSITION;
				float3 normal : NORMAL;
				float2 uv : TEXCOORD0;
			};

			struct v2f {
				float4 position : SV_POSITION;
				float3 lightVec : TEXCOORD0;
				float3 worldPos : TEXCOORD1;
			};

			sampler3D _DitherMaskLOD;
			sampler2D _MainTex;
			float4 _MainTex_ST;

			v2f vert(appdata v)
			{
				v2f i;
				i.position = UnityObjectToClipPos(v.vertex);
				i.lightVec =
					mul(unity_ObjectToWorld, v.vertex).xyz - _LightPositionRange.xyz;
				i.position = UnityClipSpaceShadowCasterPos(v.vertex.xyz, v.normal);
				i.position = UnityApplyLinearShadowBias(i.position);
				i.worldPos = mul(unity_ObjectToWorld, v.vertex);
				return i;
			}

			fixed4 frag(v2f i) : SV_Target
			{
				
				float2 uv = (i.worldPos.xz * 0.00004) + float2(0.5, 0.5);
				fixed4 col = tex2D(_MainTex, uv);
				float alpha = 1.66 * (clamp(4 * max(col.r, col.g) - 1.2, 0.0, 0.6));

				float dither =
					tex3D(_DitherMaskLOD, float3(i.position.xy * 0.25, alpha * 0.9375)).a;
				clip(dither - 0.01);

				SHADOW_CASTER_FRAGMENT(i);
				
			}
			ENDCG
		}
	}
}
