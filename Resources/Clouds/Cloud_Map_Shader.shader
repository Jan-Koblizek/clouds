/*
Copyright (c) 2020 Jan Koblížek

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
*/

Shader "Unlit/CloudMapShader"
{
    Properties
	{
		//Cloud map rendered in the previous frame
		[HideInInspector]_MainTex("RenderTexture", 2D) = "white" {}
		//Amount and thickeness of the clouds
		[HideInInspector]_Coverage("Coverage", float) = 0.5
		//Coverage we would like to change the sky to
		[HideInInspector]_CoverageChangeTo("Coverage Change To", float) = 1.0
		//Position of the clouds compared to their initial position (x, y) and the direction the wind blowes (z, w)
		[HideInInspector]_PositionDirection("PositionDirection", Vector) = (0.0, 0.0, 0.0, 0.0)
		//Speed of the wind
		[HideInInspector]_Speed("Speed", float) = 0.0
		//Time since the last frame was rendered
		[HideInInspector]_DeltaTime("Delta Time", float) = 0.0
		//If this is the first time the cloud texture is rendered in this game (1) otherwise (0)
		[HideInInspector]_First("First", int) = 0
    }
    SubShader
    {
        Tags { "RenderType"="Opaque" }
        LOD 100

        Pass
        {
            CGPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            // make fog work
            #pragma multi_compile_fog

            #include "UnityCG.cginc"


			float _Coverage;
			float _CoverageChangeTo;
			float4 _PositionDirection;
			float _Speed;
			float _DeltaTime;
			int _First;
		
			float hash13(float3 p3)
			{
				p3 = frac(p3 * .1031);
				p3 += dot(p3, p3.yzx + 33.33);
				return frac((p3.x + p3.y) * p3.z);
			}


			float random(in float2 st) {
				return frac(sin(dot(st.xy,
					float2(12.9898, 78.233)))*
					43758.5453123);
			}
			//Generates the Perlin Noise with one octave
			float noise(float2 pos, int mult) {
				float2 i = floor(pos);
				float2 f = frac(pos);

				float a = random(i);
				float b = random((i + float2(1.0, 0.0)) % mult);
				float c = random((i + float2(0.0, 1.0)) % mult);
				float d = random((i + float2(1.0, 1.0)) % mult);

				float2 u = f * f * (3.0 - 2.0 * f);

				return lerp(a, b, u.x) +
					(c - a)* u.y * (1.0 - u.x) +
					(d - b) * u.x * u.y;
			}

			//Generates Perlin noise (8 octaves)
			#define OCTAVES 8
			float perlin(float2 pos, int mult) {

				float value = 0.0;
				float amplitude = .5;
				float frequency = 0.;

				for (int i = 0; i < OCTAVES; i++) {
					value += amplitude * noise(pos, mult);
					pos *= 2.;
					mult *= 2.;
					amplitude *= .5;
				}
				return value;
			}

            struct appdata
            {
                float4 vertex : POSITION;
                float2 uv : TEXCOORD0;
            };

            struct v2f
            {
                float2 uv : TEXCOORD0;
                UNITY_FOG_COORDS(1)
                float4 vertex : SV_POSITION;
            };

            sampler2D _MainTex;
            float4 _MainTex_ST;

            v2f vert (appdata v)
            {
                v2f o;
                o.vertex = UnityObjectToClipPos(v.vertex);
                o.uv = TRANSFORM_TEX(v.uv, _MainTex);
                return o;
            }

            fixed4 frag (v2f i) : SV_Target
			{
				/*
				Generates cloud map (for cummulus) using perlin noise
				*/

				/*
				The amount the clouds moved since the beginning of the game (in x and y directions)
				*/
				float2 shift = float2(_PositionDirection.x / 20000 + (_DeltaTime * _Speed * _PositionDirection.z / 20000),
									_PositionDirection.y / 20000 + (_DeltaTime * _Speed * _PositionDirection.w / 20000));
				//uv coordinates to the read from the texture
				float2 uv = (i.uv + shift) % 1;

				//The amount the clouds moved since the last frame
				float2 shiftFrame = float2(_DeltaTime * _Speed * _PositionDirection.z / 20000, _DeltaTime * _Speed * _PositionDirection.w / 20000);
				

				//If this is the first frame return perlin noise with the specified coverage output(cummulus, stratus, 0, coverage)
				if (_First == 1)
				{
					float perlinValue = clamp(perlin((uv) * 16, 16) + (0.8*_Coverage - 0.5), 0., 1.);
					return float4(pow(perlinValue, pow(2 - 2*perlinValue, 1)), 0., 0., _Coverage);
				}
				//Not the first frame - use already rendered cloud-map
				else {
					float coverage;
					coverage = tex2D(_MainTex, i.uv).a;

					//If we are not at the edge - copy coverage from the corresponding uv in the texture we got from the last frame
					if (((i.uv + shiftFrame).x < 0.995) && ((i.uv + shiftFrame).x > 0.005) && ((i.uv + shiftFrame).y < 0.995) && ((i.uv + shiftFrame).y > 0.005))
					{
						coverage = tex2D(_MainTex, i.uv + shiftFrame).a;
					}
					//If we are at the edge - move coverage towards the goal (_CoverageChangeTo)
					else {
						float2 vectorToEdge = normalize(i.uv - float2(0.5, 0.5));
						float2 wind = normalize(float2(_PositionDirection.z, _PositionDirection.w));
						coverage = tex2D(_MainTex, i.uv).a + clamp(0.001 * (_CoverageChangeTo - tex2D(_MainTex, i.uv).a), 0.0001, 0.001) * clamp(dot(vectorToEdge, wind), 0.2, 1.) * _Speed / 100;
					}

					//Return perlin noise with the coverage we got from the previous condition
					float perlinValue = clamp(perlin((uv) * 16, 16) + (0.8*coverage - 0.5), 0., 1.);
					return float4(pow(perlinValue, pow(2 - 2 * perlinValue, 1)), 0., 0., coverage);
				}

                //return half4(pow(fbm((uv) * 16, 16), pow(2.4 - 2 * fbm((uv) * 16, 16), 1)), 0., 0., 1.);
            }
            ENDCG
        }
    }
}
