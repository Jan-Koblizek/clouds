Shader "Unlit/Sun_Shafts"
{
    Properties
	{
		_MainTex("Texture", 2D) = "white" {}
		_ColorBuffer ("Texture", 2D) = "white" {}
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

	fixed4 fragSunShaftSource(v2f i) : SV_Target
	{
		float depth00 = SAMPLE_DEPTH_TEXTURE(_CameraDepthTexture, (i.uv.xy));
		depth00 = Linear01Depth(depth00);
		/*
		float depth01 = SAMPLE_DEPTH_TEXTURE(_CameraDepthTexture, (i.uv.xy + fixed2(0, _MainTex_TexelSize.y)));
		float depth02 = SAMPLE_DEPTH_TEXTURE(_CameraDepthTexture, (i.uv.xy + fixed2(0, 2 * _MainTex_TexelSize.y)));
		float depth03 = SAMPLE_DEPTH_TEXTURE(_CameraDepthTexture, (i.uv.xy + fixed2(0, 3 * _MainTex_TexelSize.y)));

		float depth10 = SAMPLE_DEPTH_TEXTURE(_CameraDepthTexture, (i.uv.xy + fixed2(_MainTex_TexelSize.x, 0)));
		float depth11 = SAMPLE_DEPTH_TEXTURE(_CameraDepthTexture, (i.uv.xy + fixed2(_MainTex_TexelSize.x, _MainTex_TexelSize.y)));
		float depth12 = SAMPLE_DEPTH_TEXTURE(_CameraDepthTexture, (i.uv.xy + fixed2(_MainTex_TexelSize.x, 2 * _MainTex_TexelSize.y)));
		float depth13 = SAMPLE_DEPTH_TEXTURE(_CameraDepthTexture, (i.uv.xy + fixed2(_MainTex_TexelSize.x, 3 * _MainTex_TexelSize.y)));

		float depth20 = SAMPLE_DEPTH_TEXTURE(_CameraDepthTexture, (i.uv.xy + fixed2(2 * _MainTex_TexelSize.x, 0)));
		float depth21 = SAMPLE_DEPTH_TEXTURE(_CameraDepthTexture, (i.uv.xy + fixed2(2 * _MainTex_TexelSize.x, _MainTex_TexelSize.y)));
		float depth22 = SAMPLE_DEPTH_TEXTURE(_CameraDepthTexture, (i.uv.xy + fixed2(2 * _MainTex_TexelSize.x, 2 * _MainTex_TexelSize.y)));
		float depth23 = SAMPLE_DEPTH_TEXTURE(_CameraDepthTexture, (i.uv.xy + fixed2(2 * _MainTex_TexelSize.x, 3 * _MainTex_TexelSize.y)));

		float depth30 = SAMPLE_DEPTH_TEXTURE(_CameraDepthTexture, (i.uv.xy + fixed2(3 * _MainTex_TexelSize.x, 0)));
		float depth31 = SAMPLE_DEPTH_TEXTURE(_CameraDepthTexture, (i.uv.xy + fixed2(3 * _MainTex_TexelSize.x, _MainTex_TexelSize.y)));
		float depth32 = SAMPLE_DEPTH_TEXTURE(_CameraDepthTexture, (i.uv.xy + fixed2(3 * _MainTex_TexelSize.x, 2 * _MainTex_TexelSize.y)));
		float depth33 = SAMPLE_DEPTH_TEXTURE(_CameraDepthTexture, (i.uv.xy + fixed2(3 * _MainTex_TexelSize.x, 3 * _MainTex_TexelSize.y)));
		
		depth01 = Linear01Depth(depth01);
		depth02 = Linear01Depth(depth02);
		depth03 = Linear01Depth(depth03);

		depth10 = Linear01Depth(depth10);
		depth11 = Linear01Depth(depth11);
		depth12 = Linear01Depth(depth12);
		depth13 = Linear01Depth(depth13);

		depth20 = Linear01Depth(depth20);
		depth21 = Linear01Depth(depth21);
		depth22 = Linear01Depth(depth22);
		depth23 = Linear01Depth(depth23);

		depth30 = Linear01Depth(depth30);
		depth31 = Linear01Depth(depth31);
		depth32 = Linear01Depth(depth32);
		depth33 = Linear01Depth(depth33);

		float depth = (depth00 + depth01 + depth02 + depth03 +
					   depth10 + depth11 + depth12 + depth13 +
					   depth20 + depth21 + depth22 + depth23 +
					   depth30 + depth31 + depth32 + depth33) / 16;
		*/
		
		
		half dist = saturate(_SunPosition.w - length(_SunPosition.xy - i.uv.xy));
		fixed4 col = 0;
		if (depth00 > 0.9)
		{
			col = tex2D(_MainTex, i.uv);
			col = dot(pow(max(col.rgb - half3(0.8, 0.8, 0.8), half3(0.0, 0.0, 0.0)), 0.5), half3(1,1,1))*(_SunColor+0.4*col)*dist;
		}
		return col * 0.5 * _ShaftsStrength;
	}

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
