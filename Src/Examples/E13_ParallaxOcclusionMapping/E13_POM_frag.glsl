#version 450
#extension GL_ARB_separate_shader_objects  : enable
#extension GL_ARB_shading_language_420pack : enable

// https://learnopengl.com/Advanced-Lighting/Parallax-Mapping
// https://web.archive.org/web/20190131000650/https://www.sunandblackcat.com/tipFullView.php?topicid=28

layout (binding = 0)    uniform     sampler2D   SamplerNormalMap;		// [INPUT_TEXTURE_NORMAL]
layout (binding = 1)    uniform     sampler2D   SamplerDiffuseMap;		// [INPUT_TEXTURE_DIFFUSE]
layout (binding = 2)    uniform     sampler2D   SamplerAOMap;			// [INPUT_TEXTURE_AO]
layout (binding = 3)    uniform     sampler2D   SamplerGlossivessMap;	// [INPUT_TEXTURE_GLOSSINESS]
layout (binding = 4)    uniform     sampler2D   SamplerDepthMap;		// [INPUT_TEXTURE_DEPTH]

layout(location = 0) in struct 
{ 
    vec3 TangentPosition;
    vec3 TangentView;
    vec3 TangentLight;

    vec4  VertColor;
    vec2  UV; 
} In;

layout (push_constant) uniform PushConsts 
{
    mat4  L2C;
    vec4  LocalSpaceLightPos;
    vec4  LocalSpaceEyePos;
	vec4  AmbientLightColor;
	vec4  LightColor;
} pushConsts;

layout (location = 0)   out         vec4        outFragColor;

float Shininess = 20.9f;

//-------------------------------------------------------------------------------------------

vec2 ParallaxMapping(vec2 texCoords, vec3 viewDir)
{ 
	const float height_scale = 0.1f;

	//
	// Try to minizice the iterations
	//
	const float minLayers = 8.0;
	const float maxLayers = 15.0;
	float numLayers = mix(maxLayers, minLayers, max(dot(vec3(0.0, 0.0, 1.0), viewDir), 0.0));

	//
	// Steep parallax mapping 
	//

    // calculate the size of each layer
    float layerDepth = 1.0 / numLayers;

    // depth of current layer
    float currentLayerDepth = 0.0;

    // the amount to shift the texture coordinates per layer (from vector P)
    vec2 P = viewDir.xy * height_scale; 
    vec2 deltaTexCoords = P / numLayers;
  
	// get initial values
	vec2  currentTexCoords     = texCoords;
	float currentDepthMapValue = texture(SamplerDepthMap, currentTexCoords).r;
  
	while(currentLayerDepth < currentDepthMapValue)
	{
		// shift texture coordinates along direction of P
		currentTexCoords -= deltaTexCoords;
		// get depthmap value at current texture coordinates
		currentDepthMapValue = texture(SamplerDepthMap, currentTexCoords).r;  
		// get depth of next layer
		currentLayerDepth += layerDepth;  
	}

	//
	// Parallax Occlusion Mapping
	//
	if( true ) 	// This can be disable for extra performance
	{
		// get texture coordinates before collision (reverse operations)
		vec2 prevTexCoords = currentTexCoords + deltaTexCoords;

		// get depth after and before collision for linear interpolation
		float afterDepth  = currentDepthMapValue - currentLayerDepth;
		float beforeDepth = texture(SamplerDepthMap, prevTexCoords).r - currentLayerDepth + layerDepth;
 
		// interpolation of texture coordinates
		float weight = afterDepth / (afterDepth - beforeDepth);
		vec2 finalTexCoords = prevTexCoords * weight + currentTexCoords * (1.0 - weight);
	}

	return currentTexCoords;
}


//-------------------------------------------------------------------------------------------

const float parallaxScale = 0.1f;

vec2 parallaxMapping(in vec3 V, in vec2 T, out float parallaxHeight)
{
// determine optimal number of layers
   const float minLayers = 10;
   const float maxLayers = 15;
   float numLayers = mix(maxLayers, minLayers, abs(dot(vec3(0, 0, 1), V)));

   // height of each layer
   float layerHeight = 1.0 / numLayers;
   // current depth of the layer
   float curLayerHeight = 0;
   // shift of texture coordinates for each layer
   vec2 dtex = parallaxScale * V.xy / numLayers;

   // current texture coordinates
   vec2 currentTextureCoords = T;

   // depth from heightmap
   float heightFromTexture = texture(SamplerDepthMap, currentTextureCoords).r;

   // while point is above the surface
   while(heightFromTexture > curLayerHeight)
   {
      // to the next layer
      curLayerHeight += layerHeight;
      // shift of texture coordinates
      currentTextureCoords -= dtex;
      // new depth from heightmap
      heightFromTexture = texture(SamplerDepthMap, currentTextureCoords).r;
   }

   ///////////////////////////////////////////////////////////

   // previous texture coordinates
   vec2 prevTCoords = currentTextureCoords + dtex;

   // heights for linear interpolation
   float nextH = heightFromTexture - curLayerHeight;
   float prevH = texture(SamplerDepthMap, prevTCoords).r
                           - curLayerHeight + layerHeight;

   // proportions for linear interpolation
   float weight = nextH / (nextH - prevH);

   // interpolation of texture coordinates
   vec2 finalTexCoords = prevTCoords * weight + currentTextureCoords * (1.0-weight);

   // interpolation of depth values
   parallaxHeight = curLayerHeight + prevH * weight + nextH * (1.0 - weight);

   // return result
   return finalTexCoords;
}

//-------------------------------------------------------------------------------------------

float parallaxSoftShadowMultiplier(in vec3 L, in vec2 initialTexCoord,
                                       in float initialHeight)
{
   float shadowMultiplier = 1;
   const float minLayers = 15;
   const float maxLayers = 30;

   // calculate lighting only for surface oriented to the light source
   if( dot(vec3(0, 0, 1), L) > 0 )
   {
      // calculate initial parameters
      float numSamplesUnderSurface = 0;
      shadowMultiplier = 0;
      float numLayers = mix(maxLayers, minLayers, abs(dot(vec3(0, 0, 1), L)));
      float layerHeight = initialHeight / numLayers;
      vec2 texStep = parallaxScale * L.xy  / numLayers;

      // current parameters
      float currentLayerHeight = initialHeight - layerHeight;
      vec2 currentTextureCoords = initialTexCoord + texStep;
      float heightFromTexture = texture(SamplerDepthMap, currentTextureCoords).r;
      int stepIndex = 1;

      // while point is below depth 0.0 )
      while(currentLayerHeight > 0)
      {
         // if point is under the surface
         if(heightFromTexture < currentLayerHeight)
         {
            // calculate partial shadowing factor
            numSamplesUnderSurface += 1;
            float newShadowMultiplier = (currentLayerHeight - heightFromTexture) *
                                             (1.0 - stepIndex / numLayers);
            shadowMultiplier = max(shadowMultiplier, newShadowMultiplier);
         }

         // offset to the next layer
         stepIndex += 1;
         currentLayerHeight -= layerHeight;
         currentTextureCoords += texStep;
         heightFromTexture = texture(SamplerDepthMap, currentTextureCoords).r;
      }

      // Shadowing factor should be 1 if there were no points under the surface
      if(numSamplesUnderSurface < 1)
      {
         shadowMultiplier = 1;
      }
      else
      {
         shadowMultiplier = 1.0 - shadowMultiplier;
      }
   }
   return shadowMultiplier;
}

//-------------------------------------------------------------------------------------------

void main() 
{
	// Note This is the true Eye to Texel direction 
	const vec3 EyeDirection = normalize( In.TangentPosition - In.TangentView.xyz );

	// Note that the real light direction is the negative of this, but the negative is removed to speed up the equations
	vec3 LightDirection = normalize( In.TangentLight.xyz - In.TangentPosition );

	//
	// get the parallax coordinates
	//
	vec2 texCoords;
	float Shadow;

	if( true )
	{
		texCoords	= ParallaxMapping( In.UV, EyeDirection );
		Shadow		= parallaxSoftShadowMultiplier( LightDirection, texCoords, texture(SamplerDepthMap, texCoords).r );
	}
	else
	{
		float parallaxHeight;
		texCoords	= parallaxMapping( EyeDirection, In.UV, parallaxHeight );
		Shadow		= parallaxSoftShadowMultiplier( LightDirection, texCoords, parallaxHeight );
	}

	//
	// get the normal from a compress texture (either DXT5 or 3Dc/BC5)
	//
	vec3 Normal;
	if( true )
	{
		// For BC5 it used (rg)
		Normal.xy	= (texture(SamplerNormalMap, texCoords).rg * 2.0) - 1.0;
	}
	else
	{
		// For DXT5 it uses (ag)
		Normal.xy	= (texture(SamplerNormalMap, texCoords).ag * 2.0) - 1.0;
	}
	
	// Derive the final element
	Normal.z =  sqrt(1.0 - dot(Normal.xy, Normal.xy));

	//
	// Different techniques to do Lighting
	//

	// Compute the diffuse intensity
	float DiffuseI  = max( 0, dot( Normal, LightDirection ));

	// Another way to compute specular "BLINN-PHONG" (https://learnopengl.com/Advanced-Lighting/Advanced-Lighting)
	float SpecularI  = pow( max( 0, dot(Normal, normalize( LightDirection - EyeDirection ))), Shininess);

	// Read the diffuse color
	vec4 DiffuseColor	= texture(SamplerDiffuseMap, texCoords) * In.VertColor;

	// Set the global constribution
	outFragColor.rgb  = pushConsts.AmbientLightColor.rgb * DiffuseColor.rgb * texture(SamplerAOMap, texCoords).rgb;

	// Add the contribution of this light
	outFragColor.rgb += pow( Shadow, 4.0f)  * pushConsts.LightColor.rgb * ( SpecularI.rrr *  texture(SamplerGlossivessMap, texCoords).rgb + DiffuseI.rrr * DiffuseColor.rgb );

	// Convert to gamma
	const float Gamma = pushConsts.LocalSpaceEyePos.w;
	outFragColor.a    = DiffuseColor.a;
	outFragColor.rgb  = pow( outFragColor.rgb, vec3(1.0f/Gamma) );
}


