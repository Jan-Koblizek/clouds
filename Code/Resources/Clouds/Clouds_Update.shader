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

Shader "Unlit/Clouds_Update"
{
	Properties
	{
			[HideInInspector]_Clouds_Ambient_Bottom("Ambient Bottom", Color) = (1, 1, 1, 1)
			[HideInInspector]_Clouds_Ambient_Top("Ambient Top", Color) = (1, 1, 1, 1)
			//3D noise texture used for basic cloud shapes
			[HideInInspector]_3dTexture("3D noise", 3D) = "white"
			//3D noise texture used to add smaller details
			[HideInInspector]_3dTexture_Distort("3d noise - detail", 3D) = "white"
			//2D cloud map - tells the program, the amount of clouds at each position
			[HideInInspector]_Cloud_Map("Cloud map", 2D) = "red"
			[HideInInspector]_Density("Density", Float) = 0.
			
			//Shift of the clouds from the first frame
			[HideInInspector]_PositionDirection("PositionDirection", Vector) = (0.0, 0.0, 0.0, 0.0)
			[HideInInspector]_Speed("Speed", float) = 0.0

			//Number of the current frame % 16 - used to tell which pixels are currently updated
			[HideInInspector]_FrameNumber("Frame Number", int) = 0
			[HideInInspector]_MainTex("RenderTexture", 2D) = "white"
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
			#include "Lighting.cginc"

						uniform half _HdrExposure;		// HDR exposure
						uniform half3 _GroundColor;

						half3 _Color;
						half3 _SunTint;
						half _SunStrength;

						// RGB wavelengths
						#define GAMMA .454545
						static const float MN = 2;
						static const float MX = .7;
						#define WR (0.68*lerp(MN, MX, pow(_Color.r,GAMMA)))
						#define WG (0.55*lerp(MN, MX, pow(_Color.g,GAMMA)))
						#define WB (0.44*lerp(MN, MX, pow(_Color.b,GAMMA)))

						static const float3 kInvWavelength = float3(1.0 / (WR*WR*WR*WR), 1.0 / (WG*WG*WG*WG), 1.0 / (WB*WB*WB*WB));
						#define OUTER_RADIUS 6478000.0
						static const float kOuterRadius = OUTER_RADIUS;
						static const float kOuterRadius2 = OUTER_RADIUS * OUTER_RADIUS;
						static const float kInnerRadius = 6378000.0;
						static const float kInnerRadius2 = kInnerRadius * kInnerRadius;

						static const float kCameraHeight = 0.0001;

						#define kRAYLEIGH 0.0025		// Rayleigh constant
						#define kMIE 0.0010      		// Mie constant
						#define kSUN_BRIGHTNESS 500.0 	// Sun brightness

						static const float kKrESun = kRAYLEIGH * kSUN_BRIGHTNESS;
						static const float kKmESun = kMIE * kSUN_BRIGHTNESS;
						static const float kKr4PI = kRAYLEIGH * 4.0 * 3.14159265;
						static const float kKm4PI = kMIE * 4.0 * 3.14159265;
						static const float kScale = 1.0 / (OUTER_RADIUS - 1.0);
						static const float kScaleDepth = 0.25;
						static const float kScaleOverScaleDepth = (1.0 / (OUTER_RADIUS - 1.0)) / 0.25;
						static const float kSamples = 20.0; // THIS IS UNROLLED MANUALLY, DON'T TOUCH

						#define MIE_G (-0.98)
						#define MIE_G2 0.9604

						#define CLOUD_MARCH_STEPS 64
						#define CLOUD_SELF_SHADOW_STEPS 6
						#define CLOUDS_SHADOW_MARCH_STEP_SIZE (20.)
						#define CLOUDS_SHADOW_MARCH_STEP_MULTIPLY (1.5)

						#define CLOUDS_BOTTOM   (500.)
						#define CLOUDS_TOP      (2000.)



						#define CLOUDS_DETAIL_STRENGTH (.3)
						#define CLOUDS_FORWARD_SCATTERING_G (.7)

						#define CLOUDS_MIN_TRANSMITTANCE .08

						#define CLOUDS_BASE_SCALE 1.51

						#define SCENE_SCALE (1.)
						#define SUN_COLOR _LightColor0




						sampler3D _3dTexture;
						sampler3D _3dTexture_Distort;
						int _FrameNumber;
						sampler2D _MainTex;
						uniform float4 _MainTex_TexelSize;

						float4 _PositionDirection;
						float _Speed;
						float _Density;

						float3 _Clouds_Ambient_Bottom;
						float3 _Clouds_Ambient_Top;


						sampler2D _Cloud_Map;

						float hash13(float3 p3) {
							p3 = frac(p3 * 1031.1031);
							p3 += dot(p3, p3.yzx + 19.19);
							return frac((p3.x + p3.y) * p3.z);
						}

						float scale(float inCos)
						{
							float x = 1.0 - inCos;
							return 0.25 * exp(-0.00287 + x * (0.459 + x * (3.83 + x * (-6.80 + x * 5.25))));
						}

            struct appdata
            {
                float4 vertex : POSITION;
                float2 uv : TEXCOORD0;
            };

			struct v2f {
				float4 pos : SV_POSITION;
				float2 uv : TEXCOORD0;
			};

			v2f vert(appdata v) {
				v2f OUT;
				OUT.uv = v.uv;
				OUT.pos = UnityObjectToClipPos(v.vertex);

				return OUT;
			}


			float HenyeyGreenstein(float sundotrd, float g) {
				float gg = g * g;
				return (1. - gg) / pow(1. + gg - 2. * g * sundotrd, 1.5);
			}

			float linearstep(const float s, const float e, float v) {
				return clamp((v - s)*(1. / (e - s)), 0., 1.);
			}

			float remap(float v, float s, float e) {
				return (v - s) / (e - s);
			}

			/*
			Returns distance to the intersection of the cloud plane
			*/
			float intersectClouds(float3 rd, float d) {
				return d / (rd.y + 0.01);
			}

			/*
			Cloud gradients
			cumulus - thicker slower transitions
			stratus - thinner
			*/
			float cumulusGradient(float norY) {
				return linearstep(-0.1, 0.3, norY) - linearstep(0.4, 1.2, norY);
			}

			float stratusGradient(float norY) {
				return linearstep(0.05, 0.15, norY) - linearstep(0.2, 0.25, norY);
			}
			float stratocumulusGradient(float norY) {
				return linearstep(-0.05, 0.15, norY) - linearstep(0.15, 0.65, norY);
			}

			/*
			Used to add smaller details to the clouds - Layered Voronoi
			*/
			float cloudMapDetail(float3 p) {
				float3 shift = float3(_PositionDirection.x + (_Speed * _PositionDirection.z / 20000),
					0.,
					_PositionDirection.y + (_Speed * _PositionDirection.w / 20000));
				float3 uv = (p + shift * 0.8) * (0.002 * CLOUDS_BASE_SCALE);
				float4 cloud = tex3D(_3dTexture_Distort, frac(uv));

				return 0.5*cloud.r + 0.25 * cloud.g + 0.25*cloud.b - 0.5;
			}

			/*
			Samples clouds - return value is used for cummulus as it is for stratus it is modified by the inout value detail
			inout float3 detail - Layered Voronoi texture at different frequencies - used for basic cloud shapes
			*/
			float cloudMapBase(float3 p) {
				//Shift clouds had since the first frame
				float3 shift = float3(_PositionDirection.x + (_Speed * _PositionDirection.z / 20000),
					0.,
					_PositionDirection.y + (_Speed * _PositionDirection.w / 20000));
				float3 uv = (p + shift * 0.9) * (0.0002 * CLOUDS_BASE_SCALE);
				float4 cloud = tex3D(_3dTexture, frac(uv));
				return 0.25 * cloud.r + 0.25 * cloud.g + 0.45 * cloud.b + 0.05*cloud.a;
			}

			/*
			Samples clouds for raymarch steps
			*/
			float cloudMap(float3 pos, float dist, out bool inClouds) {
				/*
				Samples the Cloud Map - red is used for cummulus and green for stratus
				*/
				inClouds = false;
				float2 uv = (pos.xz * 0.00004) + float2(0.5, 0.5);
				float4 texMap = tex2D(_Cloud_Map, (uv % 1 + float2(1.0, 1.0)) % 1);
				float cumulusMultiplier = cumulusGradient((pos.y - CLOUDS_BOTTOM) / float((CLOUDS_TOP - CLOUDS_BOTTOM))) * texMap.r;
				float stratusMultiplier = stratusGradient((pos.y - CLOUDS_BOTTOM) / float((CLOUDS_TOP - CLOUDS_BOTTOM))) * texMap.g;
				float stratocumulusMultiplier = stratocumulusGradient((pos.y - CLOUDS_BOTTOM) / float((CLOUDS_TOP - CLOUDS_BOTTOM))) * texMap.b;
				if ((cumulusMultiplier < 0.2) && (stratocumulusMultiplier < 0.2) && (stratusMultiplier < 0.2))
				{
					if (stratusMultiplier > 0.1) {
						inClouds = true;
					}
					return 0.0;
				}
				
				float m = clamp(cloudMapBase(pos), 0.5, 1.5);

				float mCumulus = m * cumulusMultiplier;
				float mStratus = m * stratusMultiplier;
				float mStratocumulus = m * stratocumulusMultiplier;
			

				
				mStratus -= 0.2;

				mCumulus *= 2;
				mCumulus -= 0.4;

				mStratocumulus *= 2;
				mStratocumulus -= 0.4;
				
				/*
				Modify the cumulus with detail 3D noise texture
				We only take detail into account if we have sampled density of the clouds > -0.1
				Otherwise small detail might appear outside of the general cloud shapes
				*/

				if (abs(mCumulus) < 0.05)
				{
					inClouds = true;
					float decreaseDetail = clamp(dist / float((CLOUDS_TOP - CLOUDS_BOTTOM)), 1.0, 20.0);
					mCumulus -= cloudMapDetail(pos) * CLOUDS_DETAIL_STRENGTH / decreaseDetail;
				}

				if (abs(mStratocumulus) < 0.05)
				{
					inClouds = true;
					float decreaseDetail = clamp(dist / float((CLOUDS_TOP - CLOUDS_BOTTOM)), 1.0, 20.0);
					mStratocumulus -= cloudMapDetail(pos) * CLOUDS_DETAIL_STRENGTH / decreaseDetail;
				}

				if (abs(mStratus) < 0.05)
				{
					inClouds = true;
					mStratus -= cloudMapDetail(pos) * CLOUDS_DETAIL_STRENGTH;
				}
				mStratus *= 2;
				mStratus *= texMap.g;

				
				return clamp(max(max(clamp(mStratus, 0., 10.), clamp(mCumulus, 0., 10.)), clamp(mStratocumulus, 0., 10.)) * _Density, 0., 1.);
			}

			/*
			Samples clouds for self shadow steps simmilar to cloudMap() function
			*/
			float cloudMapShadow(float3 pos) {
				float m = clamp(cloudMapBase(pos), 0.5, 1.5);
				float2 uv = (pos.xz * 0.00004) + float2(0.5, 0.5);
				float4 texMap = tex2D(_Cloud_Map, ((uv % 1)+float2(1.0,1.0))%1);

				float stratocumulusMultiplier = stratocumulusGradient((pos.y - CLOUDS_BOTTOM) / float((CLOUDS_TOP - CLOUDS_BOTTOM))) * texMap.b;

				float mCumulus = 2 * m * cumulusGradient((pos.y - CLOUDS_BOTTOM) / float((CLOUDS_TOP - CLOUDS_BOTTOM)));
				float mStratocumulus = 2 * m * stratocumulusMultiplier;



				mCumulus = mCumulus * texMap.r;

				float mStratus = m * texMap.g * stratusGradient((pos.y - CLOUDS_BOTTOM) / float((CLOUDS_TOP - CLOUDS_BOTTOM)));

				mStratus -= 0.2;
				mStratus *= 2;
				mStratus *= texMap.g;

				mCumulus -= 0.4;
				mStratocumulus -= 0.4;

				mCumulus = mCumulus * 0.3;
				mStratocumulus = mStratocumulus * 0.6;

				return clamp(max(max(clamp(mStratus, 0., 1.), clamp(mCumulus, 0., 0.3)), clamp(mStratocumulus, 0., 0.3)) * _Density, 0., 1.);
			}


			/*
			Takes steps towards the sun (of increasing length) and computes self shadowing in the cloud.
			*/
			float volumetricShadow(in float3 from) {
				float dd = CLOUDS_SHADOW_MARCH_STEP_SIZE;
				float3 rd;
				rd = normalize(_WorldSpaceLightPos0.xyz);
				float d = dd * .5;
				//Initial light strength
				float shadow = 2000.0 * clamp(dot(float3(0, 1, 0), rd), 0.0, 1.);

				[unroll(CLOUD_SELF_SHADOW_STEPS)]
				for (int s = 0; s < CLOUD_SELF_SHADOW_STEPS; s++) {
					float3 pos = from + rd * d;

					float muE = cloudMapShadow(pos);
					//Decreases the amount of light exponentionaly based on the length of the shadow march step and the thickness of the cloud
					shadow *= exp(-muE * dd);

					dd *= CLOUDS_SHADOW_MARCH_STEP_MULTIPLY;
					d += dd;

				}
				return shadow;
			}


			/*
			Main function for cloud generation - it ray marches and samples clouds on the way
			*/
			float4 clouds(float3 ro, float3 rd) {
				if (rd.y < 0.) {
					return float4(0, 0, 0, 10);
				}

				//Distance to the lower cloud plane
				float start = intersectClouds(rd, CLOUDS_BOTTOM - ro.y);
				float dist = start;
				//distance to the higher cloud plane
				float end = intersectClouds(rd, CLOUDS_TOP - ro.y);
				float sundotrd;
				sundotrd = dot(normalize(_WorldSpaceLightPos0.xyz), normalize(rd));


				float d = start;
				float dD = (end - start) / float(CLOUD_MARCH_STEPS);

				float h = hash13(rd);
				d -= h * dD;

				
				//gets HenyeyGreensteun scattering function - makes cloud around the sun brighter
				float scattering = HenyeyGreenstein(sundotrd, CLOUDS_FORWARD_SCATTERING_G);


				//Takes marches in the ray direction - initially the sample color is black
				//and the transmittance is 1 (clouds are totally transparent)
				float transmittance = 1.0;
				float3 scatteredLight = float3(0., 0., 0.);
				int s = 0;
				//The sample was in clouds or close to them (where they could appear just by adding detail)
				bool inClouds = false;
				bool previousClouds = false;
				
				//Uses steps of double length
				[loop]
				for (int s = 0; s < CLOUD_MARCH_STEPS / 2; s++) {
					//p is the longer step sample
					float3 p = ro + d * rd;
					//if more detail is needed add p2 in between p samples
					float3 p2 = ro + (d-dD) * rd;
					//Sample clouds at p
					float alpha = cloudMap(p, dist + 2 * s * dD, inClouds);

					//If previous step sampled clouds, this sample is still considered to be in the clouds (and smaller steps may be used)
					if (previousClouds) {
						inClouds = true;
					}
					previousClouds = false;
					//If this or previous sample was in clouds, small step sample might be used
					if ((alpha > 0.0)||inClouds) {
						//If transmittance is > 0.1 use smaller steps
						if (transmittance > 0.1) {
							float alpha2 = cloudMap(p2, dist + (2 * s - 1) * dD, inClouds);
							//If the cloud density at either sample was > 0 calculate lighting there
							if (alpha2 > 0.0)
							{
								float3 ambientLight2 = lerp(_Clouds_Ambient_Bottom, _Clouds_Ambient_Top, (p2.y - CLOUDS_BOTTOM) / float((CLOUDS_TOP - CLOUDS_BOTTOM)));
								float3 S2 = pow(SUN_COLOR, 10) * (scattering * volumetricShadow(p2)) * alpha2 + 100 * pow(ambientLight2, 4) * alpha2;
								float dTrans2 = exp(-alpha2 * dD);
								float3 Sint2 = (S2 - S2 * dTrans2) * (1. / alpha2);
								scatteredLight += transmittance * Sint2;
								transmittance *= dTrans2;
								previousClouds = true;
							}
							if (alpha > 0.0)
							{
								float3 ambientLight = lerp(_Clouds_Ambient_Bottom, _Clouds_Ambient_Top, (p.y - CLOUDS_BOTTOM) / float((CLOUDS_TOP - CLOUDS_BOTTOM)));
								float3 S = pow(SUN_COLOR, 10) * (scattering * volumetricShadow(p)) * alpha + 100 * pow(ambientLight, 4) * alpha;
								float dTrans = exp(-alpha * dD);
								float3 Sint = (S - S * dTrans) * (1. / alpha);
								scatteredLight += transmittance * Sint;
								transmittance *= dTrans;
								previousClouds = true;
							}
						}
						//If transmittance is low, just calculate lighting for the bigger step, if cloud density was greater than 0
						else if(alpha>0) {
							//Ambient light - light coming from other sources than the sun
							float3 ambientLight = lerp(_Clouds_Ambient_Bottom, _Clouds_Ambient_Top, (p.y - CLOUDS_BOTTOM) / float((CLOUDS_TOP - CLOUDS_BOTTOM)));

							float3 S = pow(SUN_COLOR, 10) * (scattering * volumetricShadow(p)) * alpha + 100 * pow(ambientLight, 4) * alpha;
							float dTrans = exp(-alpha * 2 * dD);
							float3 Sint = (S - S * dTrans) * (1. / alpha);
							scatteredLight += transmittance * Sint;
							transmittance *= dTrans;
							previousClouds = true;
						}
					}
					//If the transmittance is low the cloud march can be stopped
					if (transmittance <= CLOUDS_MIN_TRANSMITTANCE) {
						break;
					}

					d += 2*dD;

				}
				
				return float4(scatteredLight, transmittance);
			}

			fixed4 frag(v2f i) : COLOR{

				//Matrix tells program which pixels of the cloud texture should be updated this frame

				int4x4 reprojection = {
					1, 11, 3, 9,
					6, 16, 8, 14,
					2, 12, 4, 10,
					5, 15, 7, 13
				};

				//Get uv coordinates of the pixel in the cloud texture, that is updated this frame
				int pixelNumber = reprojection[_FrameNumber % 4][floor(_FrameNumber / 4)] - 1;
				int2 detailCoords = int2(pixelNumber % 4, floor(pixelNumber / 4));
				uint2 coords = int2(floor(_MainTex_TexelSize.z * i.uv.x), floor(_MainTex_TexelSize.w * i.uv.y)) * 4 + detailCoords;
				float2 uv = float2((coords.x) / (4 * _MainTex_TexelSize.z - 1), (coords.y) / (4 * _MainTex_TexelSize.w));

				//Get the eyeRay from the texture uv coordinates
				float3 cameraPos = float3(0, kInnerRadius + kCameraHeight, 0);
				float yDir = sin(uv.y*1.57);
				float distSide = sqrt(1 - yDir * yDir);
				float3 eyeRay = float3(-sin(2 * 3.14 * (uv.x)) * distSide, yDir, -cos(2 * 3.14 * (uv.x)) * distSide);

			

				float4 col2;


				if (-eyeRay.y <= 0.0)
				{
					float3 rd = eyeRay;
					float3 ro = _WorldSpaceCameraPos;
					float dist;
					//Get the clouds color and alpha
					col2 = clouds(ro, rd);
					//Tone map the cloud color
					col2.rgb = 0.2 * pow(col2.rgb, .25);
					#if defined(UNITY_COLORSPACE_GAMMA)
						col2.rgb = pow(col2.rgb, 1 / 2.2);
					#endif
				}
				return col2;
			}	

            ENDCG
        }
    }
}
