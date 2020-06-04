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
Shader "Unlit/skyTexture"
{
	Properties
	{
		//Cloud texture from the previous frame
		[HideInInspector]_MainTex("RenderTexture", 2D) = "white"
		//Update texture (shader changes 1/16th of the pixels using this)
		[HideInInspector]_UpdateTex("Texture", 2D) = "white"
		//Frame Number - used to determine which pixels should be updated
		[HideInInspector]_FrameNumber("Frame Number", int) = 0
		[HideInInspector]_Shift("Shift from previous", Vector) = (0,0,0,0)
		[HideInInspector]_First("Update of the clouds in the Start()", int) = 0
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

            #include "UnityCG.cginc"

			//Frame Number - used to determine which pixels should be updated
			int _FrameNumber;
			//Cloud texture from the previous frame
			sampler2D _MainTex;
			//Update texture (shader changes 1/16th of the pixels using this)
			sampler2D _UpdateTex;
			uniform float4 _UpdateTex_TexelSize;
			uniform float4 _MainTex_TexelSize;
			float4 _MainTex_ST;
			float4 _Shift;
			int _First;

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

            v2f vert (appdata v)
            {
                v2f o;
                o.vertex = UnityObjectToClipPos(v.vertex);
                o.uv = TRANSFORM_TEX(v.uv, _MainTex);
                return o;
            }

            fixed4 frag (v2f i) : SV_Target
            {
				fixed4 col;
				
				//Pattern used for choosing the pixel to be updated

			int4x4 reprojection = {
					1, 11, 3, 9,
					6, 16, 8, 14,
					2, 12, 4, 10,
					5, 15, 7, 13
				};

			/*
				int4x4 reprojection = {
					1, 15, 9, 7,
					8, 10, 16, 2,
					5, 3, 13, 11,
					12, 14, 4, 6
				};
			*/

				//Selecting one of the 16 pixels for update using _FrameNumber
				int x = _FrameNumber % 4;
				int y = floor(_FrameNumber / 4);
				int pixelNumber = reprojection[x][y] - 1;
				int2 detailCoords = int2(pixelNumber % 4, floor(pixelNumber / 4));
				//Getting pixel coordinates from the i.uv coordinates
				uint2 coords = int2(floor(_MainTex_TexelSize.z * i.uv.x), floor(_MainTex_TexelSize.w * i.uv.y));
				/*
				Checks, if the current pixel is one of the pixels, that should be updated this frame.
				If this is true the _UpdateTex value is returned
				Otherwise the value from the previous frame is copied
				*/
				if ((coords.x % 4 == detailCoords.x) && (coords.y % 4 == detailCoords.y)) {
					float2 uv = float2((floor(coords.x / 4) + 0.5) / (_UpdateTex_TexelSize.z), (floor(coords.y / 4) + 0.5) / (_UpdateTex_TexelSize.w));
					col = tex2D(_UpdateTex, uv);
				}
				else if (_First == 0)
				{
				//Reprojection taking cloud and camera movement into account
				float yDir = clamp(sin(i.uv.y*1.5708), 0.01, 1.0);
				float distSide = sqrt(1 - yDir * yDir);
				float3 eyeRay = float3(-sin(2 * 3.14159 * (i.uv.x)) * distSide, sin(i.uv.y*1.5708), -cos(2 * 3.14159 * (i.uv.x)) * distSide);
				float2 xzPosition = float2(eyeRay.x * 900 / yDir, eyeRay.z * 900 / yDir) + _Shift.xy;
				float3 correctedEyeRay = normalize(float3(xzPosition.x, 900, xzPosition.y));
				float y;

				//distSide = sqrt(eyeRay.x * eyeRay.x + eyeRay.z * eyeRay.z);
				y = asin(correctedEyeRay.y) / 1.5708;

				float x = ((atan2(correctedEyeRay.x, correctedEyeRay.z) + 3.14159) / (2 * 3.14159));

				col = tex2D(_MainTex, float2(x, y));
				}
				else {
					col = tex2D(_MainTex, i.uv);
				}

                return col;
            }
            ENDCG
        }
    }
}
