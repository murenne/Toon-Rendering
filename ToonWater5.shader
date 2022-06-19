Shader "Custom/ToonWater5"
{
	Properties
	{
	//_MainTex("Main Texture", 2D) = "White"{}
	 _WaveMap("Wave Map",2D) = "White"{}
	 _WaveXspeed("Wave Horizontal Speed",Range(-0.1,0.1)) = 0.01
     _WaveYspeed("Wave Vertical Speed",Range(-0.1,0.1)) = 0.01
	 _Distortion("Distortion",Range(0,5)) = 4

	_FoamTex("FoamTex",2D) = "White"{}
	_FoamTex2("FoamTex2",2D) = "White"{}
	_FoamThreshold("Foam Threshold",Range(0,2)) = 0.05
	_FoamSpeed("Foam Speed",Range(0,1)) = 0.1
	_FoamTextureSpeedX("FoamTextureSpeedX",float) = 1
	_FoamTextureSpeedY("FoamTextureSpeedY",float) = 1

	_Gross("Gross",Range(0,100)) = 1
	_SpecularColor("Specular Color",Color) = (1,1,1,1)
	_RimPower("Rim Power",Range(0,10)) = 1

	_RipplesColor("Ripples Color",Color) = (1,1,1,1)

	_Amount("Amount", Range(0.0, 1.0)) = 1.0 

	}
	 
    SubShader
	{
		Tags { "Queue"="Transparent" "RenderType"="Opaque"}
		LOD 100
		Blend SrcAlpha OneMinusSrcAlpha 

		GrabPass{"_RefractionTex"}

		Pass
		{
			CGPROGRAM
			#pragma vertex vert
			#pragma fragment frag
			// make fog work
			//#pragma multi_compile_fog
			
			#include "UnityCG.cginc"
			#include "Lighting.cginc"

			sampler2D _MainTex;
			float4 _MainTex_ST;
			sampler2D _WaveMap;
			float4 _WaveMap_ST;
			float _WaveXspeed;
			float _WaveYspeed;
			float _Distortion;
			sampler2D _RefractionTex;
            float4 _RefractionTex_TexelSize;

			sampler2D _FoamTex;
			float4 _FoamTex_ST;
			sampler2D _FoamTex2;
			float4 _FoamTex2_ST;

			float4 _SpecularColor;
			float _Gross;
			float _RimPower;

			float _FoamThreshold;
			float _FoamSpeed;
			float _FoamTextureSpeedX;
			float _FoamTextureSpeedY;

            uniform float3 _Position;
            uniform sampler2D _GlobalEffectRT;
            uniform float _OrthographicCamSize;
			float4 _RipplesColor;



			sampler2D _ReflectionTex;
            half4 _ReflectionTex_TexelSize;

			float _Amount;

			struct a2v
			{
				float4 vertex : POSITION;
                float3 normal : NORMAL;
                float4 tangent : TANGENT;
				float4 texcoord : TEXCOORD0;							
			};

			struct v2f
			{
				float4 pos : SV_POSITION;
				float4 screenPos : TEXCOORD1;
				float4 uv :TEXCOORD2;
				float4 TtoW0 : TEXCOORD3;  
				float4 TtoW1 : TEXCOORD4;  
				float4 TtoW2 : TEXCOORD5; 
                //UNITY_FOG_COORDS(6)
			};
			
			v2f vert (a2v v)
			{
				v2f o;
				o.pos = UnityObjectToClipPos(v.vertex);				
				//UNITY_TRANSFER_FOG(o,o.vertex);

				o.uv.xy = TRANSFORM_TEX(v.texcoord,_FoamTex);
				o.uv.zw = TRANSFORM_TEX(v.texcoord,_WaveMap);

				float3 worldPos = mul(unity_ObjectToWorld, v.vertex).xyz;	
				float3 worldNormal = UnityObjectToWorldNormal(v.normal);
                float3 worldTangent = UnityObjectToWorldDir(v.tangent).xyz;
                float3 worldBionormal = cross(worldNormal , worldTangent) * v.tangent.w;

                o.TtoW0 = float4(worldTangent.x , worldBionormal.x , worldNormal.x , worldPos.x);
                o.TtoW1 = float4(worldTangent.y , worldBionormal.y , worldNormal.y , worldPos.y);
                o.TtoW2 = float4(worldTangent.z , worldBionormal.z , worldNormal.z , worldPos.z);

				o.screenPos = ComputeScreenPos(o.pos);	//使用屏幕空间位置（ScreenPositin）来采样深度纹理
				COMPUTE_EYEDEPTH(o.screenPos.z);//计算eye space 的深度值写入（）
				return o;
			}

			//利用cos生成的渐变色，使用网站：https://sp4ghet.github.io/grad/
			fixed4 cosine_gradient(float x,  fixed4 phase, fixed4 amp, fixed4 freq, fixed4 offset)
            {
				const float TAU = 2. * 3.14159265;
  				phase *= TAU;
  				x *= TAU;

  				return fixed4(
    				offset.r + amp.r * 0.5 * cos(x * freq.r + phase.r) + 0.5,
    				offset.g + amp.g * 0.5 * cos(x * freq.g + phase.g) + 0.5,
    				offset.b + amp.b * 0.5 * cos(x * freq.b + phase.b) + 0.5,
    				offset.a + amp.a * 0.5 * cos(x * freq.a + phase.a) + 0.5
  				);
			}
			fixed3 toRGB(fixed3 grad)
            {
  				 return grad.rgb;
			}



			UNITY_DECLARE_DEPTH_TEXTURE(_CameraDepthTexture);
			
			fixed4 frag (v2f i) : SV_Target
			{

				float3 worldPos = float3 (i.TtoW0.w, i.TtoW1.w, i.TtoW2.w);
				fixed4 col = (1,1,1,1);
    			float sceneZ = LinearEyeDepth(SAMPLE_DEPTH_TEXTURE_PROJ(_CameraDepthTexture, UNITY_PROJ_COORD(i.screenPos)));//场景深度（沙滩）线性
				float partZ = i.screenPos.z;//片元深度（水面）
				float diffZ = saturate( (sceneZ - partZ)/10.0f);//片元深度与场景深度的差值，5.0是最大深度，可写成变量_DepthMaxDistance进行调整
                //float4 waterColor = lerp(_DepthGradientShallow, _DepthGradientDeep, diffZ);用lerp插值
				float radioZ =  partZ/sceneZ;



				//创建颜色
				const fixed4 phases = fixed4(0.28, 0.50, 0.07, 0);//周期 //const用来修饰变量为常量变量。表示const修饰的变量初始化之后，其值不会改变。
				const fixed4 amplitudes = fixed4(4.02, 0.34, 0.65, 0);//振幅
				const fixed4 frequencies = fixed4(0.00, 0.48, 0.08, 0);//频率
				const fixed4 offsets = fixed4(0.00, 0.16, 0.00, 0);//相位
				//按照距离海滩远近叠加渐变色
				fixed4 cos_grad = cosine_gradient(saturate(1.5-diffZ), phases, amplitudes, frequencies, offsets);
  				cos_grad = clamp(cos_grad, 0, 1);
  				col.rgb = toRGB(cos_grad);

				//海浪波动
				//float3 worldViewDir = normalize(_WorldSpaceCameraPos - worldPos);
				float3 worldViewDir = normalize(UnityWorldSpaceViewDir(worldPos));
				float speed = _Time.y *  float2(_WaveXspeed,_WaveYspeed);
				float3 tangentNormal1 = UnpackNormal(tex2D(_WaveMap,i.uv.zw + speed)).rgb;
				float3 tangentNormal2 = UnpackNormal(tex2D(_WaveMap,i.uv.zw - speed)).rgb;
				float3 tangentNormal = normalize(tangentNormal1 + tangentNormal2);
				float3 worldNormal = normalize(half3(dot(i.TtoW0.xyz, tangentNormal), dot(i.TtoW1.xyz, tangentNormal), dot(i.TtoW2.xyz, tangentNormal))); 
				float3 NdotV = normalize(dot(worldNormal,worldViewDir));

				//反射天空盒
                half3 reflDir = reflect(-worldViewDir, worldNormal);
				fixed4 reflectionColor = UNITY_SAMPLE_TEXCUBE(unity_SpecCube0, reflDir);

				//反射物体 + 折射物体
				float2 offset = tangentNormal.xy  *100*  _Distortion  *_ReflectionTex_TexelSize.xy ; 
				//i.screenPos.xy += pow(offset,2) * saturate(diffZ)  ;
				i.screenPos.xy =  offset  + i.screenPos.xy; 
                fixed4 reflectionColor2 = tex2D(_ReflectionTex, i.screenPos.xy / i.screenPos.w);//反射
				reflectionColor = (reflectionColor + reflectionColor2) ;

				float2 offset2 = tangentNormal.xy  *100*  _Distortion  *_RefractionTex_TexelSize.xy ; 
				i.screenPos.xy =  offset* i.screenPos.z  + i.screenPos.xy; 
				fixed4 refrCol = tex2D (_RefractionTex,i.screenPos.xy / i.screenPos.w); //透视除法，得到折射的颜色





				//涟漪
				float2 uv = worldPos.xz - _Position.xz;
                uv = uv/(_OrthographicCamSize *2);
                uv += 0.5;
				float ripples = tex2D(_GlobalEffectRT, uv ).b;
				ripples *=_RipplesColor.a;
				ripples = step(0.99, ripples*3 );
				col += ripples;




                //岸边浪花, _Time.y符号控制海浪方向，除以0.1是不想再弄一个foamDiff
				float foamDiff = saturate(diffZ / _FoamThreshold);
				fixed4 foamTexture1 = tex2D(_FoamTex, float2(i.uv.x , i.uv.y + _Time.y * _FoamTextureSpeedX)- float2(1.11,1.01));
				float foam1 = saturate(sin((foamDiff + foamTexture1.g * 0.3 + _Time.y * _FoamSpeed) * 8 * UNITY_PI)) * foamTexture1.r * (1.0 - foamDiff);
				foam1 = step(0.5,foam1);
				col += foam1;

				float4 foamTexture2 = tex2D(_FoamTex2, worldPos.xy * _FoamTex2_ST.xy +  _Time.y * float2(_FoamTextureSpeedX, _FoamTextureSpeedY));
				float foam2 = step(foamDiff /0.1- (saturate(sin((foamDiff/0.1 + _Time.y * _FoamSpeed) * 8 * UNITY_PI)) * (1.0 - foamDiff/0.1)), foamTexture2);  // 1-foamDiff 为了让中间是空的和一些噪点
				col += foam2;

				//高光
				float3 worldlightDir = normalize(UnityWorldSpaceLightDir(worldPos));
				float3 halfDir = normalize(worldlightDir + worldViewDir);
				fixed3 specular = _LightColor0.rgb * _SpecularColor.rgb  * pow(max(0,dot(worldNormal,halfDir)),_Gross);
				col += fixed4(specular,1);

				//边缘光
				float3 v = worldPos - _WorldSpaceCameraPos;
				col += ddy(length(v.xz))/2;

				// 菲涅尔反射
				float f0 = 0.02;
                float3 fresnel = saturate((f0 + (1-f0) * pow(1-saturate(NdotV),5)) * 2) *_LightColor0.rgb;	
				col =lerp(col , reflectionColor + refrCol , fixed4(fresnel,1)) ;
				


				col += fixed4(fresnel,0);//白色海浪，为什么？

				//接近海滩部分更透明
				float alpha = saturate(diffZ);			
                col.a = alpha;

				col +=ripples;

				return col ;
			}
			ENDCG
		}
	}
    
}
