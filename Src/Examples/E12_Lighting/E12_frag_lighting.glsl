#version 450
#extension GL_ARB_separate_shader_objects  : enable
#extension GL_ARB_shading_language_420pack : enable

layout (binding = 0)    uniform     sampler2D   SamplerNormalMap;		// [INPUT_TEXTURE_NORMAL]
layout (binding = 1)    uniform     sampler2D   SamplerDiffuseMap;		// [INPUT_TEXTURE_DIFFUSE]
layout (binding = 1)    uniform     sampler2D   SamplerAOMap;			// [INPUT_TEXTURE_AO]
layout (binding = 1)    uniform     sampler2D   SamplerGlossivessMap;	// [INPUT_TEXTURE_GLOSSINESS]

layout(location = 0) in struct 
{ 
    mat3  BTN;
	vec3  LocalSpacePosition;
    vec2  UV; 
} In;

layout (push_constant) uniform PushConsts 
{
    mat4 L2C;
    vec4 LocalSpaceLightPos;
    vec4 LocalSpaceEyePos;
	vec4 AmbientLightColor;
	vec4 LightColor;
} pushConsts;


layout (location = 0)   out         vec4        outFragColor;

float Shininess        = 20.9f;

void main() 
{
	vec3 Normal			= In.BTN * normalize( texture(SamplerNormalMap, In.UV).rgb * 2.0 - 1.0);

	//
	// Different techniques to do Lighting
	//

	// Note that the real light direction is the negative of this, but the negative is removed to speed up the equations
	vec3 LightDirection = normalize( pushConsts.LocalSpaceLightPos.xyz - In.LocalSpacePosition );

	// Compute the diffuse intensity
	float DiffuseI  = max( 0, dot( Normal, LightDirection ));

	// Note This is the true Eye to Texel direction 
	vec3 EyeDirection = normalize( In.LocalSpacePosition - pushConsts.LocalSpaceEyePos.xyz );

	// The old way to Compute Specular "PHONG"
	// Reflection == I - 2.0 * dot(N, I) * N // Where N = Normal, I = LightDirectioh
	float SpecularI1  = pow( max(0, dot( reflect(LightDirection, Normal), EyeDirection )), Shininess );

	// Another way to compute specular "BLINN-PHONG" (https://learnopengl.com/Advanced-Lighting/Advanced-Lighting)
	float SpecularI2  = pow( max( 0, dot(Normal, normalize( LightDirection - EyeDirection ))), Shininess);

	// Read the diffuse color
	vec4 DiffuseColor	= texture(SamplerDiffuseMap, In.UV);

	// Set the global constribution
	outFragColor.rgb  = pushConsts.AmbientLightColor.rgb * DiffuseColor.rgb * texture(SamplerAOMap, In.UV).rgb;

	// Add the contribution of this light
	outFragColor.rgb += pushConsts.LightColor.rgb * ( SpecularI2.rrr *  texture(SamplerGlossivessMap, In.UV).rgb + DiffuseI.rrr * DiffuseColor.rgb );

	// Convert to gamma
	const float gamma = 2.2f;
	outFragColor.a   = 1;
	outFragColor.rgb = pow( outFragColor.rgb, vec3(1.0f/gamma) );
}


