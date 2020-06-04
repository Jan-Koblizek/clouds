Shader "Unlit/Sun_Shafts"
{
    Properties
	{
		_MainTex("Texture", 2D) = "white" {}
		_ColorBuffer ("Texture", 2D) = "white" {}
		_Skybox("Texture", 2D) = "white" {}
    }

	CGINCLUDE

	#include "UnityCG.cginc"

	struct appdata
	{
		float4 vertex : POSITION;
		float2 uv : TEXCOORD0;
	};

	struct v2f
	{
		float2 uv : TEXCOORD0;
		float4 vertex : SV_POSITION;
	};

	sampler2D _MainTex;
	float4 _MainTex_ST;
	float4 _MainTex_TexelSize;
	sampler2D _ColorBuffer;
	sampler2D_float _CameraDepthTexture;

	sampler2D _Skybox;
	
	uniform half4 _SunColor;
	uniform half4 _Blur;
	uniform half4 _SunPosition;
	uniform float _ShaftsStrength;
	v2f vert(appdata v)
	{
		v2f o;
		o.vertex = UnityObjectToClipPos(v.vertex);
		o.uv = v.uv;
		//o.uv = TRANSFORM_TEX(v.uv, _MainTex);
		return o;
	}

	//Picks unobstructed parts of the sky.
	fixed4 fragSunShaftSource(v2f i) : SV_Target
	{
		fixed4 col = tex2D(_MainTex, i.uv);
		fixed4 sky = tex2D(_Skybox, i.uv.xy);
		float skyboxAlpha = 1 - sky.a;
		if (Luminance(abs(sky.rgb - col.rgb)) > 0.01)
		{
			return fixed4(0.0, 0.0, 0.0, 1.0);
		}
		float depth = SAMPLE_DEPTH_TEXTURE(_CameraDepthTexture, i.uv);
		depth = Linear01Depth(depth);
		col = fixed4(0.0, 0.0, 0.0, 1.0);
		half dist = saturate(_SunPosition.w - length(_SunPosition.xy - i.uv.xy));
		col = tex2D(_MainTex, i.uv)*pow(skyboxAlpha, 5);
		col = dot(pow(max(col.rgb, half3(0.0, 0.0, 0.0)), 0.5), half3(1, 1, 1))*(_SunColor + 0.4*col)*dist;
		return col * 0.1 * _ShaftsStrength;
	}

	//Adding sunshafts to the rendered image
	fixed4 fragAddSunShafts(v2f i) : SV_Target
	{
		return tex2D(_MainTex, i.uv) + tex2D(_ColorBuffer, i.uv);
	}
   


	struct v2fRadial {
		float4 pos : SV_POSITION;
		float2 uv : TEXCOORD0;
		float2 blurVector : TEXCOORD1;
	};
           
	v2fRadial vertRadial(appdata v) {
		v2fRadial o;
		o.pos = UnityObjectToClipPos(v.vertex);

		o.uv.xy = v.uv.xy;
		o.blurVector = (_SunPosition.xy - v.uv.xy) * _Blur.xy;

		return o;
	}

	//Bluring the light away from the sun dot
	half4 fragRadial(v2fRadial i) : SV_Target
	{
		half4 color = half4(0,0,0,0);
		for (int j = 0; j < 6; j++)
		{
			half4 tmpColor = tex2D(_MainTex, i.uv.xy);
			color += tmpColor;
			i.uv.xy += i.blurVector;
			if ((i.uv.x < 0) || (i.uv.x > 1) || (i.uv.y < 0) || (i.uv.y > 1)) {
				break;
			}
		}
		return color / 6.0f;
	}


	ENDCG

	SubShader
    {

        Pass
        {
			ZTest Always Cull Off ZWrite Off
            
			CGPROGRAM

            #pragma vertex vert
            #pragma fragment fragSunShaftSource

            ENDCG
        }

		Pass
		{
			ZTest Always Cull Off ZWrite Off

			CGPROGRAM

			#pragma vertex vertRadial
			#pragma fragment fragRadial

			ENDCG
		}

		Pass
		{
			ZTest Always Cull Off ZWrite Off

			CGPROGRAM

			#pragma vertex vert
			#pragma fragment fragAddSunShafts

			ENDCG
		}
    }
	Fallback off
}
